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

class ExamScreen extends StatefulWidget {
  final Map<String, dynamic> params;
  const ExamScreen({super.key, required this.params});
  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  ExamState _state = ExamState.loading;
  List<Map<String, dynamic>> _questions = [];
  Map<int, String> _userAnswers = {};
  int _currentQ = 0;
  int _timeLeft = 0;
  Timer? _timer;
  bool _submitting = false;

  // ETA for generation
  int _generateProgress = 0;
  String _generateMsg = 'MCQ তৈরি হচ্ছে...';
  Timer? _etaTimer;

  late int _pdfId;
  late List<int> _pageNumbers;
  late String _mcqType;
  late bool _practiceMode;
  late bool _mistakeOnly;
  late int? _practiceExamId;

  @override
  void initState() {
    super.initState();
    _pdfId = widget.params['pdf_id'] ?? 0;
    _pageNumbers = List<int>.from(widget.params['page_numbers'] ?? [1]);
    _mcqType = widget.params['mcq_type'] ?? 'standard';
    _practiceMode = widget.params['practice_mode'] ?? false;
    _mistakeOnly = widget.params['mistake_only'] ?? false;
    _practiceExamId = widget.params['exam_id'];
    _loadMcqs();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _etaTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMcqs() async {
    setState(() => _state = ExamState.loading);

    // Practice mode: load from exam history
    if (_practiceMode && _practiceExamId != null) {
      await _loadPracticeQuestions();
      return;
    }

    // Check offline cache first
    final pageNum = _pageNumbers.first;
    final cached = await OfflineService.getCachedMcqs(_pdfId, pageNum, _mcqType);
    if (cached.isNotEmpty) {
      _prepareQuestions(cached);
      return;
    }

    // Fetch from server
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

        // Disabled type
        if (data['disabled'] == true) {
          if (mounted) {
            _showDisabledDialog(data['message'] ?? '');
          }
          return;
        }

        // Still generating
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
          // Cache for offline
          await OfflineService.cacheMcqs(_pdfId, _pageNumbers.first, _mcqType, mcqs);
          _prepareQuestions(mcqs);
        } else {
          _startEtaPolling();
        }
      }
    } catch (_) {
      // Offline — try cache
      final cached = await OfflineService.getCachedMcqs(
          _pdfId, _pageNumbers.first, _mcqType);
      if (cached.isNotEmpty) {
        _prepareQuestions(cached);
      } else {
        setState(() { _state = ExamState.generating; _generateMsg = 'সংযোগ নেই। ক্যাশ খুঁজছে...'; });
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
        final questions = List<Map<String, dynamic>>.from(data['questions'] ?? []);
        _prepareQuestions(questions);
      }
    } catch (_) {}
  }

  void _prepareQuestions(List<Map<String, dynamic>> mcqs) {
    // For multi-page exams, combine
    setState(() {
      _questions = mcqs;
      _timeLeft = mcqs.length * 60; // 1 min per question
      _state = ExamState.ready;
    });
  }

  void _startEtaPolling() {
    _etaTimer?.cancel();
    _etaTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      setState(() => _generateProgress = (_generateProgress + 10).clamp(0, 95));
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
              await OfflineService.cacheMcqs(_pdfId, _pageNumbers.first, _mcqType, mcqs);
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

  void _selectAnswer(String option) {
    setState(() => _userAnswers[_currentQ] = option);
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
        title: const Text('জমা দিবে?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('উত্তর দিয়েছো: ${_userAnswers.length}/${_questions.length}',
                style: const TextStyle(color: Colors.white70)),
            if (unanswered > 0) ...[
              const SizedBox(height: 8),
              Text('$unanswered টি উত্তর বাদ আছে',
                  style: const TextStyle(color: Colors.orange)),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('ফিরে যাও')),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); _submitExam(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('জমা দাও'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitExam() async {
    _timer?.cancel();
    setState(() { _submitting = true; _state = ExamState.submitted; });

    // Calculate results
    int correct = 0;
    final answers = <Map<String, dynamic>>[];
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final userAns = _userAnswers[i];
      final correctAns = q['correct_answer'] as String? ?? 'A';
      final isCorrect = userAns == correctAns;
      if (isCorrect) correct++;
      answers.add({
        'mcq_id': q['id'],
        'question': q['question'],
        'option_a': q['option_a'], 'option_b': q['option_b'],
        'option_c': q['option_c'], 'option_d': q['option_d'],
        'correct_answer': correctAns,
        'user_answer': userAns,
        'is_correct': isCorrect ? 1 : 0,
        'explanation': q['explanation'] ?? '',
        'page_number': q['page_number'] ?? _pageNumbers.first,
      });
    }

    final score = _questions.isEmpty ? 0.0 : (correct / _questions.length) * 100;

    // Submit to server
    try {
      final token = await AuthService.getToken();
      final res = await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/exam/submit'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'pdf_id': _pdfId,
          'page_numbers': _pageNumbers.join(','),
          'mcq_type': _mcqType,
          'total_questions': _questions.length,
          'correct_answers': correct,
          'score': score,
          'answers': answers,
        }),
      );
      if (res.statusCode != 200 && res.statusCode != 201) {
        // Queue for offline sync
        await OfflineService.addPendingSync('exam_result', {
          'pdf_id': _pdfId,
          'page_numbers': _pageNumbers.join(','),
          'mcq_type': _mcqType,
          'total_questions': _questions.length,
          'correct_answers': correct,
          'score': score,
          'answers': answers,
        });
      }
    } catch (_) {
      await OfflineService.addPendingSync('exam_result', {
        'pdf_id': _pdfId, 'page_numbers': _pageNumbers.join(','),
        'mcq_type': _mcqType, 'total_questions': _questions.length,
        'correct_answers': correct, 'score': score, 'answers': answers,
      });
    }

    setState(() => _submitting = false);
  }

  void _showDisabledDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Coming Soon 🔒',
            style: TextStyle(color: Colors.white)),
        content: Text(msg.isNotEmpty ? msg : 'এই MCQ ধরন এখনো চালু হয়নি',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); context.pop(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('ঠিক আছে'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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

  // ─── LOADING ──────────────────────────────────────────────
  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('লোড হচ্ছে...', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  // ─── GENERATING ETA ───────────────────────────────────────
  Widget _buildGenerating() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withOpacity(0.15),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.amber, size: 40),
          ),
          const SizedBox(height: 24),
          Text(_generateMsg,
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('AI দিয়ে তোমার জন্য MCQ তৈরি হচ্ছে',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
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
              style: TextStyle(color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
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
            child: const Text('ফিরে যাও', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // ─── READY (Pre-message) ──────────────────────────────────
  Widget _buildReady() {
    final typeLabel = {'standard': 'Standard MCQ', 'true_false': 'True/False', 'hard': 'Hard'}[_mcqType] ?? 'MCQ';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppTheme.primaryColor, AppTheme.primaryColor.withOpacity(0.5)]),
            ),
            child: const Icon(Icons.quiz_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 24),
          Text(
            _practiceMode ? 'Practice Mode' : 'পরীক্ষা শুরু!',
            style: const TextStyle(color: Colors.white, fontSize: 24,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                _infoRow('📝 ধরন', typeLabel),
                _infoRow('❓ প্রশ্ন', '${_questions.length}টি'),
                _infoRow('⏱️ সময়', _formatTime(_timeLeft)),
                _infoRow('📄 পৃষ্ঠা', _pageNumbers.join(', ')),
                if (_practiceMode)
                  _infoRow('🎯 মোড', _mistakeOnly ? 'ভুলগুলো Practice' : 'সব Practice'),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startExam,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('শুরু করো ▶',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('বাতিল করো', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // ─── ACTIVE EXAM ──────────────────────────────────────────
  Widget _buildActive() {
    if (_questions.isEmpty) return _buildLoading();
    final q = _questions[_currentQ];
    final userAns = _userAnswers[_currentQ];
    final isLast = _currentQ == _questions.length - 1;
    final timeWarning = _timeLeft < 60;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: AppTheme.bgColor,
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: _confirmSubmit,
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_currentQ + 1) / _questions.length,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${_currentQ + 1}/${_questions.length}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: timeWarning
                      ? Colors.red.withOpacity(0.2)
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatTime(_timeLeft),
                  style: TextStyle(
                    color: timeWarning ? Colors.red : Colors.white70,
                    fontWeight: FontWeight.bold, fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('পৃষ্ঠা ${q['page_number'] ?? '-'}',
                      style: TextStyle(color: AppTheme.primaryColor, fontSize: 11)),
                ),
                const SizedBox(height: 14),
                // Question
                Text(q['question'] ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
                const SizedBox(height: 24),
                // Options
                ...(['A', 'B', 'C', 'D']).map((opt) {
                  final key = 'option_${opt.toLowerCase()}';
                  final text = (q[key] ?? '') as String;
                  if (text.isEmpty) return const SizedBox.shrink();
                  final isSelected = userAns == opt;
                  return GestureDetector(
                    onTap: () => _selectAnswer(opt),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 12),
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
                      child: Row(
                        children: [
                          Container(
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primaryColor
                                  : Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(opt,
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(text,
                                style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontSize: 14)),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 18),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        // Bottom nav
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D1A),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(
            children: [
              if (_currentQ > 0)
                OutlinedButton(
                  onPressed: _prevQuestion,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('← আগে'),
                ),
              const Spacer(),
              // Answer dots
              Wrap(
                spacing: 4,
                children: List.generate(
                  _questions.length > 10 ? 10 : _questions.length,
                  (i) => Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _userAnswers.containsKey(i)
                          ? AppTheme.primaryColor
                          : (i == _currentQ ? Colors.white54 : Colors.white12),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _nextQuestion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLast ? Colors.green : AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: Text(isLast ? 'জমা দাও ✓' : 'পরের →'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── RESULT ───────────────────────────────────────────────
  Widget _buildResult() {
    if (_submitting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('ফলাফল সেভ হচ্ছে...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    int correct = 0;
    for (int i = 0; i < _questions.length; i++) {
      if (_userAnswers[i] == _questions[i]['correct_answer']) correct++;
    }
    final score = _questions.isEmpty ? 0.0 : (correct / _questions.length) * 100;
    final isGood = score >= 70;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Score circle
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                isGood ? Colors.green : Colors.red,
                (isGood ? Colors.green : Colors.red).withOpacity(0.5),
              ]),
              boxShadow: [
                BoxShadow(
                  color: (isGood ? Colors.green : Colors.red).withOpacity(0.4),
                  blurRadius: 30, spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${score.toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontSize: 28,
                        fontWeight: FontWeight.bold)),
                Text('$correct/${_questions.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isGood ? '🎉 চমৎকার!' : score >= 50 ? '👍 ভালো চেষ্টা' : '💪 আরো পড়ো',
            style: const TextStyle(color: Colors.white, fontSize: 22,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          // Stats
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                _infoRow('✅ সঠিক', '$correct টি'),
                _infoRow('❌ ভুল', '${_questions.length - correct} টি'),
                _infoRow('📊 স্কোর', '${score.toStringAsFixed(1)}%'),
                _infoRow('📝 MCQ ধরন',
                    {'standard':'Standard','true_false':'True/False','hard':'Hard'}[_mcqType]??''),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/exam-detail', extra: {
                    'questions': _questions.asMap().entries.map((e) => {
                      ...e.value,
                      'user_answer': _userAnswers[e.key],
                      'is_correct': _userAnswers[e.key] == e.value['correct_answer'] ? 1 : 0,
                    }).toList(),
                    'score': score,
                    'total_questions': _questions.length,
                    'correct_answers': correct,
                  }),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('বিস্তারিত'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _state = ExamState.loading;
                      _userAnswers = {};
                      _currentQ = 0;
                    });
                    _loadMcqs();
                  },
                  icon: const Icon(Icons.replay, size: 16),
                  label: const Text('আবার দাও'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('হোমে যাও', style: TextStyle(color: Colors.white38)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}
