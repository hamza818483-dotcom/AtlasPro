import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/offline_service.dart';

enum ExamState { loading, generating, ready, active, submitted }

const _banglaLabels = ['ক', 'খ', 'গ', 'ঘ', 'ঙ'];
const _optionKeys = ['option_a', 'option_b', 'option_c', 'option_d', 'option_e'];
const _optionCodes = ['A', 'B', 'C', 'D', 'E'];

class ExamScreen extends StatefulWidget {
  final Map<String, dynamic> params;
  const ExamScreen({super.key, required this.params});
  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen>
    with SingleTickerProviderStateMixin {
  ExamState _state = ExamState.loading;
  List<Map<String, dynamic>> _questions = [];
  Map<int, String> _userAnswers = {};
  int _currentQ = 0;
  int _timeLeft = 0;
  Timer? _timer;
  bool _submitting = false;

  int _generateProgress = 0;
  String _generateMsg = 'MCQ তৈরি হচ্ছে...';
  Timer? _etaTimer;

  late int _pdfId;
  late List<int> _pageNumbers;
  late String _mcqType;
  late bool _practiceMode;
  late bool _mistakeOnly;
  late int? _practiceExamId;

  // Result state
  String _resultFilter = 'all';
  Map<int, bool> _explanationExpanded = {};
  Map<int, String> _explanations = {};
  Map<int, bool> _explanationLoading = {};

  // GPA
  final _sscCtrl = TextEditingController();
  final _hscCtrl = TextEditingController();
  double? _gpaScore;

  // Timer pulse animation
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pdfId = widget.params['pdf_id'] ?? 0;
    _pageNumbers = List<int>.from(widget.params['page_numbers'] ?? [1]);
    _mcqType = widget.params['mcq_type'] ?? 'standard';
    _practiceMode = widget.params['practice_mode'] ?? false;
    _mistakeOnly = widget.params['mistake_only'] ?? false;
    _practiceExamId = widget.params['exam_id'];

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _loadMcqs();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _etaTimer?.cancel();
    _pulseCtrl.dispose();
    _sscCtrl.dispose();
    _hscCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMcqs() async {
    setState(() => _state = ExamState.loading);
    if (_practiceMode && _practiceExamId != null) {
      await _loadPracticeQuestions();
      return;
    }
    final pageNum = _pageNumbers.first;
    final cached = await OfflineService.getCachedMcqs(_pdfId, pageNum, _mcqType);
    if (cached.isNotEmpty) {
      _prepareQuestions(cached);
      return;
    }
    await _fetchFromServer();
  }

  Future<void> _fetchFromServer() async {
    try {
      final token = await AuthService.getToken();
      final pageNum = _pageNumbers.first;
      final res = await http.get(
        Uri.parse(
          '${AppConstants.workerBaseUrl}/api/exam/mcq'
          '?pdf_id=$_pdfId&page_number=$pageNum&type=$_mcqType'
          '&exam_count=${AppConstants.mcqExamSize}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['disabled'] == true) {
          if (mounted) _showDisabledDialog(data['message'] ?? '');
          return;
        }
        if (data['generating'] == true) {
          setState(() {
            _state = ExamState.generating;
            _generateProgress = data['progress'] ?? 0;
            _generateMsg = data['message'] ?? 'MCQ তৈরি হচ্ছে...';
          });
          _startEtaPolling();
          return;
        }
        final mcqs = List<Map<String, dynamic>>.from(data['mcqs'] ?? []);
        if (mcqs.isNotEmpty) {
          await OfflineService.cacheMcqs(_pdfId, _pageNumbers.first, _mcqType, mcqs);
          _prepareQuestions(mcqs);
        } else {
          _startEtaPolling();
        }
      }
    } catch (_) {
      final cached = await OfflineService.getCachedMcqs(
          _pdfId, _pageNumbers.first, _mcqType);
      if (cached.isNotEmpty) {
        _prepareQuestions(cached);
      } else {
        setState(() {
          _state = ExamState.generating;
          _generateMsg = 'সংযোগ নেই। ক্যাশ খুঁজছে...';
        });
      }
    }
  }

  Future<void> _loadPracticeQuestions() async {
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse(
            '${AppConstants.workerBaseUrl}/api/exam/answers/$_practiceExamId'
            '?mistake_only=$_mistakeOnly'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final questions =
            List<Map<String, dynamic>>.from(data['questions'] ?? []);
        _prepareQuestions(questions);
      }
    } catch (_) {}
  }

  void _prepareQuestions(List<Map<String, dynamic>> mcqs) {
    setState(() {
      _questions = mcqs;
      _timeLeft = mcqs.length * 60;
      _state = ExamState.ready;
    });
  }

  void _startEtaPolling() {
    _etaTimer?.cancel();
    _etaTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      setState(
          () => _generateProgress = (_generateProgress + 10).clamp(0, 95));
      final token = await AuthService.getToken();
      try {
        final res = await http.get(
          Uri.parse(
            '${AppConstants.workerBaseUrl}/api/exam/mcq'
            '?pdf_id=$_pdfId&page_number=${_pageNumbers.first}&type=$_mcqType',
          ),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['generating'] != true && data['mcqs'] != null) {
            _etaTimer?.cancel();
            final mcqs = List<Map<String, dynamic>>.from(data['mcqs']);
            if (mcqs.isNotEmpty) {
              await OfflineService.cacheMcqs(
                  _pdfId, _pageNumbers.first, _mcqType, mcqs);
              _prepareQuestions(mcqs);
            }
          } else if (data['generating'] == true) {
            setState(() {
              _generateProgress = data['progress'] ?? _generateProgress;
              _generateMsg = data['message'] ?? _generateMsg;
            });
          }
        }
      } catch (_) {}
    });
  }

  void _startExam() {
    setState(() => _state = ExamState.active);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timeLeft <= 0) {
        _submitExam();
      } else {
        setState(() => _timeLeft--);
      }
    });
  }

  void _selectAnswer(String code) {
    setState(() => _userAnswers[_currentQ] = code);
  }

  void _goToQuestion(int idx) {
    setState(() => _currentQ = idx);
    Navigator.of(context).pop();
  }

  void _nextQuestion() {
    if (_currentQ < _questions.length - 1) {
      setState(() => _currentQ++);
    } else {
      _confirmSubmit();
    }
  }

  void _prevQuestion() {
    if (_currentQ > 0) setState(() => _currentQ--);
  }

  void _confirmSubmit() {
    final unanswered = _questions.length - _userAnswers.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('জমা দিবে?',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogRow('উত্তর দিয়েছো', '${_userAnswers.length}/${_questions.length}',
                Colors.green),
            if (unanswered > 0)
              _dialogRow('বাদ আছে', '$unanswered টি', Colors.orange),
            const SizedBox(height: 8),
            Text('নেগেটিভ মার্কিং: -০.২৫',
                style: TextStyle(
                    color: Colors.red.withOpacity(0.7), fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ফিরে যাও',
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitExam();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('জমা দাও'),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _submitExam() async {
    _timer?.cancel();
    setState(() {
      _submitting = true;
      _state = ExamState.submitted;
    });

    int correct = 0;
    int wrong = 0;
    final answers = <Map<String, dynamic>>[];

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final userAns = _userAnswers[i];
      final correctAns = q['correct_answer'] as String? ?? 'A';
      final isCorrect = userAns != null && userAns == correctAns;
      final isSkipped = userAns == null;
      if (isCorrect) correct++;
      if (!isCorrect && !isSkipped) wrong++;
      answers.add({
        'mcq_id': q['id'],
        'question': q['question'],
        'option_a': q['option_a'],
        'option_b': q['option_b'],
        'option_c': q['option_c'],
        'option_d': q['option_d'],
        'correct_answer': correctAns,
        'user_answer': userAns,
        'is_correct': isCorrect ? 1 : 0,
        'explanation': q['explanation'] ?? '',
        'page_number': q['page_number'] ?? _pageNumbers.first,
      });
    }

    final rawScore = correct - (wrong * 0.25);
    final score =
        _questions.isEmpty ? 0.0 : (rawScore / _questions.length) * 100;

    try {
      final token = await AuthService.getToken();
      final res = await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/exam/submit'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'pdf_id': _pdfId,
          'page_numbers': _pageNumbers.join(','),
          'mcq_type': _mcqType,
          'total_questions': _questions.length,
          'correct_answers': correct,
          'wrong_answers': wrong,
          'score': score,
          'answers': answers,
        }),
      );
      if (res.statusCode != 200 && res.statusCode != 201) {
        await _queueOfflineSync(correct, wrong, score, answers);
      }
    } catch (_) {
      await _queueOfflineSync(correct, wrong, score, answers);
    }

    setState(() => _submitting = false);
  }

  Future<void> _queueOfflineSync(
      int correct, int wrong, double score, List answers) async {
    await OfflineService.addPendingSync('exam_result', {
      'pdf_id': _pdfId,
      'page_numbers': _pageNumbers.join(','),
      'mcq_type': _mcqType,
      'total_questions': _questions.length,
      'correct_answers': correct,
      'wrong_answers': wrong,
      'score': score,
      'answers': answers,
    });
  }

  Future<void> _loadExplanation(int idx) async {
    if (_explanations.containsKey(idx)) return;
    setState(() => _explanationLoading[idx] = true);
    try {
      final q = _questions[idx];
      final token = await AuthService.getToken();
      final res = await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/ai/explain'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'question': q['question'],
          'correct_answer': q['correct_answer'],
          'option_a': q['option_a'],
          'option_b': q['option_b'],
          'option_c': q['option_c'],
          'option_d': q['option_d'],
          'explanation': q['explanation'] ?? '',
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _explanations[idx] = data['explanation'] ?? '');
      } else {
        final fallback = q['explanation'] as String? ?? '';
        setState(() =>
            _explanations[idx] = fallback.isNotEmpty ? fallback : 'ব্যাখ্যা পাওয়া যায়নি।');
      }
    } catch (_) {
      final fallback = _questions[idx]['explanation'] as String? ?? '';
      setState(() =>
          _explanations[idx] = fallback.isNotEmpty ? fallback : 'সংযোগ নেই।');
    }
    setState(() => _explanationLoading[idx] = false);
  }

  void _calculateGpa() {
    final ssc = double.tryParse(_sscCtrl.text) ?? 0;
    final hsc = double.tryParse(_hscCtrl.text) ?? 0;
    setState(() => _gpaScore = (ssc * 8) + (hsc * 12));
  }

  void _showDisabledDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Coming Soon 🔒',
            style: TextStyle(color: Colors.white)),
        content: Text(
            msg.isNotEmpty ? msg : 'এই MCQ ধরন এখনো চালু হয়নি',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor),
            child: const Text('ঠিক আছে'),
          ),
        ],
      ),
    );
  }

  void _showNavGrid() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('প্রশ্ন নেভিগেশন',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const Spacer(),
                Row(children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 4),
                  const Text('উত্তর দিয়েছো',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(width: 10),
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 4),
                  const Text('বাদ',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ],
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _questions.length,
              itemBuilder: (_, i) {
                final answered = _userAnswers.containsKey(i);
                final isCurrent = i == _currentQ;
                return GestureDetector(
                  onTap: () => _goToQuestion(i),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppTheme.accentColor
                          : answered
                              ? AppTheme.primaryColor
                              : Colors.white12,
                      borderRadius: BorderRadius.circular(6),
                      border: isCurrent
                          ? Border.all(color: Colors.white, width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 11)),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmSubmit();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: Text(
                    'জমা দাও (${_userAnswers.length}/${_questions.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _banglaLabel(int optIdx) =>
      optIdx < _banglaLabels.length ? _banglaLabels[optIdx] : '?';

  String _banglaForCode(String code) {
    final idx = _optionCodes.indexOf(code);
    return idx >= 0 ? _banglaLabels[idx] : code;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: SafeArea(
        child: switch (_state) {
          ExamState.loading => _buildLoading(),
          ExamState.generating => _buildGenerating(),
          ExamState.ready => _buildReady(),
          ExamState.active => _buildActive(),
          ExamState.submitted => _buildResult(),
        },
      ),
    );
  }

  // ─── LOADING ──────────────────────────────────────────────────
  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFF818CF8), Color(0xFFC4B5FD), Color(0xFFF472B6)],
            ).createShader(b),
            child: const Text('ATLAS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6)),
          ),
          const SizedBox(height: 32),
          CircularProgressIndicator(color: AppTheme.primaryColor),
          const SizedBox(height: 16),
          const Text('লোড হচ্ছে...', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  // ─── GENERATING ───────────────────────────────────────────────
  Widget _buildGenerating() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppTheme.primaryColor.withOpacity(0.3),
                AppTheme.primaryColor.withOpacity(0.05),
              ]),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 44),
          ),
          const SizedBox(height: 24),
          Text(_generateMsg,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('AI দিয়ে তোমার জন্য MCQ তৈরি হচ্ছে',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _generateProgress / 100,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 8),
          Text('$_generateProgress%',
              style: TextStyle(
                  color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: const Text(
              '⏳ একবার তৈরি হলে আজীবন সেভ থাকবে।\nপরের বার তাৎক্ষণিক শুরু হবে।',
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('ফিরে যাও',
                style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // ─── READY ────────────────────────────────────────────────────
  Widget _buildReady() {
    final typeLabel = {
          'standard': 'Standard MCQ',
          'true_false': 'True/False',
          'hard': 'Hard MCQ'
        }[_mcqType] ??
        'MCQ';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFF818CF8), Color(0xFFC4B5FD), Color(0xFFF472B6)],
            ).createShader(b),
            child: const Text('ATLAS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6)),
          ),
          const SizedBox(height: 24),
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.accentColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.4),
                    blurRadius: 24,
                    spreadRadius: 4),
              ],
            ),
            child: const Icon(Icons.quiz_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 20),
          Text(
            _practiceMode ? 'Practice Mode' : 'পরীক্ষা শুরু!',
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(typeLabel,
              style: TextStyle(color: AppTheme.primaryColor, fontSize: 13)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(children: [
              _infoRow('📝 ধরন', typeLabel),
              _infoRow('❓ প্রশ্ন', '${_questions.length}টি'),
              _infoRow('⏱️ সময়', _formatTime(_timeLeft)),
              _infoRow('📄 পৃষ্ঠা', _pageNumbers.join(', ')),
              _infoRow('⚠️ নেগেটিভ', 'ভুলে -০.২৫'),
              if (_practiceMode)
                _infoRow('🎯 মোড', _mistakeOnly ? 'ভুলগুলো Practice' : 'সব Practice'),
            ]),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startExam,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('শুরু করো ▶',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('বাতিল করো',
                style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // ─── ACTIVE EXAM ──────────────────────────────────────────────
  Widget _buildActive() {
    if (_questions.isEmpty) return _buildLoading();
    final q = _questions[_currentQ];
    final userAns = _userAnswers[_currentQ];
    final isLast = _currentQ == _questions.length - 1;
    final timeWarning = _timeLeft < 60;
    final answeredCount = _userAnswers.length;

    return Stack(
      children: [
        Column(
          children: [
            // ── Sticky Timer Header ──
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0A0A14), Color(0xFF13132A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))
                ],
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Row(children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 22),
                      onPressed: _confirmSubmit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 10),
                    // ATLAS brand
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                          colors: [
                            Color(0xFF818CF8),
                            Color(0xFFC4B5FD),
                            Color(0xFFF472B6)
                          ]).createShader(b),
                      child: const Text('ATLAS',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 3)),
                    ),
                    const Spacer(),
                    // Timer
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, __) => Transform.scale(
                        scale: timeWarning ? _pulseAnim.value : 1.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: timeWarning
                                  ? [
                                      Colors.red.withOpacity(0.3),
                                      Colors.red.withOpacity(0.15)
                                    ]
                                  : [
                                      AppTheme.primaryColor.withOpacity(0.2),
                                      AppTheme.primaryColor.withOpacity(0.08)
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: timeWarning
                                    ? Colors.red.withOpacity(0.5)
                                    : AppTheme.primaryColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            _formatTime(_timeLeft),
                            style: TextStyle(
                              color: timeWarning ? Colors.red : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Score counter
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$answeredCount/${_questions.length}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                // Progress bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_currentQ + 1) / _questions.length,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                      minHeight: 4,
                    ),
                  ),
                ),
              ]),
            ),

            // ── Question Body ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Q number + page badge
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            AppTheme.primaryColor,
                            AppTheme.accentColor
                          ]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('প্রশ্ন ${_currentQ + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                            'পৃষ্ঠা ${q['page_number'] ?? '-'}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11)),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    // Question text
                    Text(q['question'] ?? '',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16, height: 1.6)),
                    const SizedBox(height: 20),
                    // Options ক/খ/গ/ঘ
                    ...List.generate(_optionKeys.length, (optIdx) {
                      final key = _optionKeys[optIdx];
                      final code = _optionCodes[optIdx];
                      final text = (q[key] ?? '') as String;
                      if (text.isEmpty) return const SizedBox.shrink();
                      final isSelected = userAns == code;
                      return GestureDetector(
                        onTap: () => _selectAnswer(code),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryColor.withOpacity(0.15)
                                : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : Colors.white.withOpacity(0.1),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? AppTheme.primaryColor
                                    : Colors.transparent,
                                border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryColor
                                        : Colors.white38,
                                    width: 1.5),
                              ),
                              child: Center(
                                child: Text(_banglaLabel(optIdx),
                                    style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white60,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(text,
                                  style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 14,
                                      height: 1.4)),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle,
                                  color: AppTheme.primaryColor, size: 18),
                          ]),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // ── Bottom Nav ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                border: Border(
                    top: BorderSide(color: Colors.white.withOpacity(0.06))),
              ),
              child: Row(children: [
                if (_currentQ > 0)
                  OutlinedButton(
                    onPressed: _prevQuestion,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('← আগে'),
                  ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _nextQuestion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isLast ? Colors.green : AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(isLast ? 'জমা দাও ✓' : 'পরের →',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          ],
        ),

        // ── Navigation FAB ──
        Positioned(
          right: 12,
          bottom: 80,
          child: FloatingActionButton.small(
            onPressed: _showNavGrid,
            backgroundColor: const Color(0xFF2A2A3E),
            foregroundColor: Colors.white,
            elevation: 4,
            child: const Icon(Icons.grid_view_rounded, size: 20),
          ),
        ),
      ],
    );
  }

  // ─── RESULT ───────────────────────────────────────────────────
  Widget _buildResult() {
    if (_submitting) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: AppTheme.primaryColor),
          const SizedBox(height: 16),
          const Text('ফলাফল সেভ হচ্ছে...',
              style: TextStyle(color: Colors.white54)),
        ]),
      );
    }

    int correct = 0;
    int wrong = 0;
    for (int i = 0; i < _questions.length; i++) {
      final ans = _userAnswers[i];
      final corr = _questions[i]['correct_answer'] as String? ?? 'A';
      if (ans != null && ans == corr) {
        correct++;
      } else if (ans != null) {
        wrong++;
      }
    }
    final skipped = _questions.length - correct - wrong;
    final rawScore = correct - (wrong * 0.25);
    final pct = _questions.isEmpty
        ? 0.0
        : (rawScore / _questions.length) * 100;
    final isGood = pct >= 70;

    final filteredEntries = _questions.asMap().entries.where((e) {
      final ans = _userAnswers[e.key];
      final corr = e.value['correct_answer'] as String? ?? 'A';
      if (_resultFilter == 'correct') return ans == corr;
      if (_resultFilter == 'wrong')
        return ans != null && ans != corr;
      if (_resultFilter == 'skipped') return ans == null;
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(children: [
        // Score card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isGood
                  ? [const Color(0xFF1A3A2A), const Color(0xFF0D2018)]
                  : pct >= 50
                      ? [const Color(0xFF2A2A14), const Color(0xFF1A1A0A)]
                      : [const Color(0xFF3A1A1A), const Color(0xFF200D0D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: (isGood ? Colors.green : pct >= 50 ? Colors.amber : Colors.red)
                    .withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                  color: (isGood
                              ? Colors.green
                              : pct >= 50
                                  ? Colors.amber
                                  : Colors.red)
                          .withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2),
            ],
          ),
          child: Column(children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                  colors: [Color(0xFF818CF8), Color(0xFFC4B5FD), Color(0xFFF472B6)],
              ).createShader(b),
              child: const Text('ATLAS',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 4)),
            ),
            const SizedBox(height: 16),
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: isGood
                      ? Colors.green
                      : pct >= 50
                          ? Colors.amber
                          : Colors.red,
                  fontSize: 48,
                  fontWeight: FontWeight.w900),
            ),
            Text(
              isGood ? '🎉 চমৎকার!' : pct >= 50 ? '👍 ভালো চেষ্টা' : '💪 আরো পড়ো',
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(children: [
              _statBox('✅', '$correct', 'সঠিক', Colors.green),
              const SizedBox(width: 8),
              _statBox('❌', '$wrong', 'ভুল', Colors.red),
              const SizedBox(width: 8),
              _statBox('⏭️', '$skipped', 'বাদ', Colors.grey),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('নেগেটিভ: ${(wrong * 0.25).toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                  Text('নেট স্কোর: ${rawScore.toStringAsFixed(2)}/${_questions.length}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ]),
        ),

        const SizedBox(height: 16),

        // GPA Calculator
        _buildGpaSection(pct),

        const SizedBox(height: 16),

        // Filter tabs
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            _filterTab('all', 'সব (${_questions.length})'),
            _filterTab('correct', '✅ ($correct)'),
            _filterTab('wrong', '❌ ($wrong)'),
            _filterTab('skipped', '⏭️ ($skipped)'),
          ]),
        ),

        const SizedBox(height: 16),

        // Questions review
        ...filteredEntries.map((e) => _buildReviewCard(e.key, e.value)),

        const SizedBox(height: 20),

        // Action buttons
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _state = ExamState.loading;
                  _userAnswers = {};
                  _currentQ = 0;
                  _explanationExpanded = {};
                  _explanations = {};
                  _explanationLoading = {};
                  _gpaScore = null;
                });
                _loadMcqs();
              },
              icon: const Icon(Icons.replay, size: 16),
              label: const Text('আবার দাও'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: BorderSide(color: AppTheme.primaryColor),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => context.go('/home'),
              icon: const Icon(Icons.home, size: 16),
              label: const Text('হোমে'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _statBox(String emoji, String count, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(count,
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _filterTab(String value, String label) {
    final active = _resultFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _resultFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppTheme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: active ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }

  Widget _buildGpaSection(double pct) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('📊 GPA ক্যালকুলেটর',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(height: 4),
        const Text('ভর্তি পরীক্ষার স্কোর হিসাব করো',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _gpaInput('SSC GPA', 'যেমন: ৫.০', _sscCtrl),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _gpaInput('HSC GPA', 'যেমন: ৫.০', _hscCtrl),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _calculateGpa,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Icon(Icons.calculate, size: 18),
          ),
        ]),
        if (_gpaScore != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withOpacity(0.2),
                    AppTheme.accentColor.withOpacity(0.1)
                  ]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('GPA ছাড়া স্কোর',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 11)),
                  Text('${pct.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ]),
                Container(
                    width: 1,
                    height: 36,
                    color: Colors.white12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('GPA সহ মোট স্কোর',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 11)),
                  Text(
                    (pct + _gpaScore!).toStringAsFixed(2),
                    style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 20),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('SSC×8 + HSC×12 = ${_gpaScore!.toStringAsFixed(2)}',
              style:
                  const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _gpaInput(String label, String hint, TextEditingController ctrl) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
          filled: true,
          fillColor: Colors.white.withOpacity(0.06),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ]);
  }

  Widget _buildReviewCard(int idx, Map<String, dynamic> q) {
    final userAns = _userAnswers[idx];
    final correctAns = q['correct_answer'] as String? ?? 'A';
    final isCorrect = userAns != null && userAns == correctAns;
    final isSkipped = userAns == null;

    Color borderColor =
        isCorrect ? Colors.green : isSkipped ? Colors.grey : Colors.red;
    Color bgColor = isCorrect
        ? Colors.green.withOpacity(0.06)
        : isSkipped
            ? Colors.white.withOpacity(0.03)
            : Colors.red.withOpacity(0.06);

    final explanationOpen = _explanationExpanded[idx] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: borderColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCorrect ? '✅ সঠিক' : isSkipped ? '⏭️ বাদ' : '❌ ভুল',
                  style: TextStyle(
                      color: borderColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text('প্রশ্ন ${idx + 1}',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11)),
              const Spacer(),
              Text('পৃষ্ঠা ${q['page_number'] ?? '-'}',
                  style: const TextStyle(
                      color: Colors.white24, fontSize: 11)),
            ]),
            const SizedBox(height: 10),
            Text(q['question'] ?? '',
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.5)),
            const SizedBox(height: 12),
            // Options review
            ...List.generate(_optionKeys.length, (optIdx) {
              final key = _optionKeys[optIdx];
              final code = _optionCodes[optIdx];
              final text = (q[key] ?? '') as String;
              if (text.isEmpty) return const SizedBox.shrink();
              final isUser = userAns == code;
              final isCorrectOpt = code == correctAns;
              Color? optColor;
              if (isCorrectOpt) optColor = Colors.green;
              if (isUser && !isCorrectOpt) optColor = Colors.red;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: optColor != null
                      ? optColor.withOpacity(0.12)
                      : Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: optColor != null
                          ? optColor.withOpacity(0.4)
                          : Colors.white.withOpacity(0.06)),
                ),
                child: Row(children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: optColor != null
                          ? optColor
                          : Colors.white.withOpacity(0.08),
                    ),
                    child: Center(
                      child: Text(_banglaLabel(optIdx),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            color: optColor != null
                                ? Colors.white
                                : Colors.white60,
                            fontSize: 13)),
                  ),
                  if (isCorrectOpt)
                    const Icon(Icons.check, color: Colors.green, size: 16),
                  if (isUser && !isCorrectOpt)
                    const Icon(Icons.close, color: Colors.red, size: 16),
                ]),
              );
            }),

            if (!isSkipped && userAns != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Text('তোমার উত্তর: ${_banglaForCode(userAns)}',
                    style: TextStyle(
                        color: isCorrect ? Colors.green : Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Text('সঠিক: ${_banglaForCode(correctAns)}',
                    style: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ]),
            ] else if (isSkipped) ...[
              const SizedBox(height: 8),
              Text('সঠিক উত্তর: ${_banglaForCode(correctAns)}',
                  style: const TextStyle(
                      color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ]),
        ),

        // AI Explanation toggle
        GestureDetector(
          onTap: () {
            final open = !(explanationOpen);
            setState(() => _explanationExpanded[idx] = open);
            if (open) _loadExplanation(idx);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14)),
              border: Border(
                  top: BorderSide(
                      color: AppTheme.primaryColor.withOpacity(0.12))),
            ),
            child: Row(children: [
              Icon(Icons.auto_awesome,
                  color: AppTheme.primaryColor, size: 14),
              const SizedBox(width: 6),
              Text('AI ব্যাখ্যা',
                  style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Icon(
                explanationOpen
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: AppTheme.primaryColor,
                size: 18,
              ),
            ]),
          ),
        ),

        if (explanationOpen) ...[
          Container(
            padding: const EdgeInsets.all(14),
            child: _explanationLoading[idx] == true
                ? Row(children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryColor),
                    ),
                    const SizedBox(width: 10),
                    const Text('ব্যাখ্যা লোড হচ্ছে...',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ])
                : Text(_explanations[idx] ?? '',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.6)),
          ),
        ],
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ]),
    );
  }
}
