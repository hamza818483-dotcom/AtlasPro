import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

enum TimerState { idle, running, onBreak, ended }

class FocusTimerScreen extends StatefulWidget {
  const FocusTimerScreen({super.key});
  @override
  State<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends State<FocusTimerScreen>
    with TickerProviderStateMixin {
  TimerState _state = TimerState.idle;
  int _studySeconds = 0;
  int _breakSeconds = 0;
  int _breaksUsed = 0;
  static const int _maxBreaks = 3;
  static const int _maxBreakSeconds = 3600; // 1 hour

  Timer? _timer;
  List<Map<String, dynamic>> _activeStudents = [];
  bool _loadingStudents = false;
  Timer? _studentRefreshTimer;
  String? _sessionId;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _loadCurrentUser();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _studentRefreshTimer?.cancel();
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    if (_state == TimerState.running || _state == TimerState.onBreak) {
      _endSession(silent: true);
    }
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUser = {
        'name': prefs.getString('user_name') ?? 'Student',
        'hsc_batch': prefs.getString('hsc_batch') ?? '',
        'college_name': prefs.getString('college_name') ?? '',
        'profile_pic': prefs.getString('profile_pic'),
        'gender': prefs.getString('gender') ?? 'male',
      };
    });
  }

  Future<void> _startSession() async {
    final token = await AuthService.getToken();
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/focus/start'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _sessionId = data['session_id']?.toString();
      }
    } catch (_) {}

    setState(() {
      _state = TimerState.running;
      _studySeconds = 0;
      _breakSeconds = 0;
      _breaksUsed = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _studySeconds++);
    });

    _startStudentRefresh();
  }

  void _startStudentRefresh() {
    _loadActiveStudents();
    _studentRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadActiveStudents(),
    );
  }

  Future<void> _loadActiveStudents() async {
    if (_loadingStudents) return;
    setState(() => _loadingStudents = true);
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/focus/active'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _activeStudents =
              List<Map<String, dynamic>>.from(data['students'] ?? []);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingStudents = false);
  }

  Future<void> _startBreak() async {
    if (_breaksUsed >= _maxBreaks) {
      _showMaxBreakDialog();
      return;
    }
    _timer?.cancel();
    setState(() {
      _state = TimerState.onBreak;
      _breakSeconds = 0;
      _breaksUsed++;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _breakSeconds++;
        if (_breakSeconds >= _maxBreakSeconds) {
          _endSession(reason: 'break_exceeded');
        }
      });
    });
    // Update server
    final token = await AuthService.getToken();
    await http.post(
      Uri.parse('${AppConstants.workerBaseUrl}/api/focus/break'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'session_id': _sessionId}),
    );
  }

  Future<void> _resumeFromBreak() async {
    _timer?.cancel();
    setState(() {
      _state = TimerState.running;
      _breakSeconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _studySeconds++);
    });
    final token = await AuthService.getToken();
    await http.post(
      Uri.parse('${AppConstants.workerBaseUrl}/api/focus/resume'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'session_id': _sessionId}),
    );
  }

  Future<void> _endSession({String? reason, bool silent = false}) async {
    _timer?.cancel();
    _studentRefreshTimer?.cancel();

    if (!silent) {
      setState(() => _state = TimerState.ended);
    }

    final token = await AuthService.getToken();
    try {
      await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/focus/end'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'session_id': _sessionId,
          'study_seconds': _studySeconds,
          'breaks_used': _breaksUsed,
          'reason': reason ?? 'manual',
        }),
      );
    } catch (_) {}
  }

  void _confirmEnd() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('⏹️ টাইমার বন্ধ করবে?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'পড়েছো: ${_formatTime(_studySeconds)}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              'বন্ধ করলে এই সেশন শেষ হয়ে যাবে এবং আর চালু করা যাবে না।',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('ফিরে যাও'),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _endSession();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('হ্যাঁ, বন্ধ করো'),
          ),
        ],
      ),
    );
  }

  void _showMaxBreakDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('⚠️ সর্বোচ্চ ব্রেক',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        content: const Text(
          'তুমি সর্বোচ্চ ৩টি ব্রেক নিয়েছো। আর ব্রেক নেওয়া যাবে না।',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor),
            child: const Text('ঠিক আছে'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: _state == TimerState.idle
          ? _buildIdleScreen()
          : _state == TimerState.ended
              ? _buildEndedScreen()
              : _buildActiveScreen(),
    );
  }

  // ─── IDLE SCREEN ─────────────────────────────────────────
  Widget _buildIdleScreen() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 32),
            // Info card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withOpacity(0.15),
                    AppTheme.accentColor.withOpacity(0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppTheme.primaryColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('⏱️', style: TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'ATLAS Focus Timer',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...[
                    ('📌 উদ্দেশ্য',
                        'পড়ার সময় ট্র্যাক করো এবং অন্য সক্রিয় শিক্ষার্থীদের সাথে যুক্ত থাকো।'),
                    ('💡 গুরুত্ব',
                        'গবেষণায় দেখা গেছে, অন্যদের সাথে একসাথে পড়লে মনোযোগ ৪০% বেড়ে যায়।'),
                    ('🔴 ব্রেক সিস্টেম',
                        'সর্বোচ্চ ৩টি ব্রেক নিতে পারবে, প্রতিটি সর্বোচ্চ ১ ঘণ্টা।'),
                    ('📊 ব্যবহার',
                        'শুরু করো → পড়ো → প্রয়োজনে ব্রেক নাও → শেষে বন্ধ করো। ইতিহাস প্রোফাইলে সেভ থাকবে।'),
                  ].map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.$1,
                                style: TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(item.$2,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Start button
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                scale: _pulseAnim.value,
                child: child,
              ),
              child: GestureDetector(
                onTap: _startSession,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.primaryColor,
                        AppTheme.primaryColor.withOpacity(0.7),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.5),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 56),
                      Text(
                        'শুরু করো',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── ACTIVE SCREEN ────────────────────────────────────────
  Widget _buildActiveScreen() {
    final isBreak = _state == TimerState.onBreak;
    return SafeArea(
      child: Column(
        children: [
          _buildActiveHeader(isBreak),
          // Main timer display
          Expanded(
            flex: 2,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isBreak ? '☕ বিরতি' : '📖 পড়ছো',
                    style: TextStyle(
                      color: isBreak ? Colors.amber : AppTheme.primaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: _glowAnim,
                    builder: (_, child) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: (isBreak ? Colors.amber : AppTheme.primaryColor)
                                .withOpacity(_glowAnim.value * 0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                    child: Text(
                      isBreak
                          ? _formatTime(_breakSeconds)
                          : _formatTime(_studySeconds),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        shadows: [
                          Shadow(
                            color: (isBreak
                                    ? Colors.amber
                                    : AppTheme.primaryColor)
                                .withOpacity(0.8),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isBreak)
                    Text(
                      'মোট পড়া: ${_formatTime(_studySeconds)}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 14),
                    ),
                  const SizedBox(height: 4),
                  // Break indicator dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _maxBreaks,
                      (i) => Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _breaksUsed
                              ? Colors.amber
                              : Colors.white12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ব্রেক: $_breaksUsed/$_maxBreaks',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 12),
                  ),
                  if (isBreak && _breakSeconds > 0) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _breakSeconds / _maxBreakSeconds,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(
                        _breakSeconds > _maxBreakSeconds * 0.8
                            ? Colors.red
                            : Colors.amber,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'বাকি: ${_formatTime(_maxBreakSeconds - _breakSeconds)}',
                      style: const TextStyle(
                          color: Colors.amber, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Active students list
          Expanded(
            flex: 3,
            child: _buildStudentsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveHeader(bool isBreak) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A14),
        border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: Colors.white54),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ATLAS Focus Timer',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              Text(
                isBreak ? 'বিরতিতে আছো' : 'সক্রিয় পড়ার সেশন',
                style: TextStyle(
                    color:
                        isBreak ? Colors.amber : AppTheme.primaryColor,
                    fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          // Break button
          if (!isBreak)
            GestureDetector(
              onTap: _breaksUsed < _maxBreaks ? _startBreak : _showMaxBreakDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.coffee, color: Colors.amber, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Break নাও',
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            )
          else
            GestureDetector(
              onTap: _resumeFromBreak,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.play_arrow, color: Colors.green, size: 14),
                    SizedBox(width: 4),
                    Text('আবার শুরু করো',
                        style: TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 8),
          // End button
          GestureDetector(
            onTap: _confirmEnd,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.stop, color: Colors.red, size: 14),
                  SizedBox(width: 4),
                  Text('বন্ধ করো',
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsList() {
    final onBreakStudents =
        _activeStudents.where((s) => s['status'] == 'break').toList();
    final studyingStudents =
        _activeStudents.where((s) => s['status'] != 'break').toList();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Text('ATLAS Focus Timer',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'সক্রিয়: ${studyingStudents.length} জন',
                    style: const TextStyle(
                        color: Colors.green,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                if (onBreakStudents.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'ব্রেকে: ${onBreakStudents.length} জন',
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _activeStudents.isEmpty
                ? const Center(
                    child: Text('কেউ এখন পড়ছে না',
                        style: TextStyle(color: Colors.white38)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _activeStudents.length,
                    itemBuilder: (ctx, i) =>
                        _buildStudentTile(_activeStudents[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentTile(Map<String, dynamic> student) {
    final isBreak = student['status'] == 'break';
    final seconds = student['study_seconds'] as int? ?? 0;
    final picUrl = student['profile_pic'] as String?;
    final name = student['name'] ?? 'Student';
    final gender = student['gender'] ?? 'male';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBreak
              ? Colors.amber.withOpacity(0.2)
              : Colors.green.withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.primaryColor.withOpacity(0.15),
                backgroundImage:
                    picUrl != null ? NetworkImage(picUrl) : null,
                child: picUrl == null
                    ? Text(
                        gender == 'female' ? '👩' : '👨',
                        style: const TextStyle(fontSize: 18),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isBreak ? Colors.amber : Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0A0A14), width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                Text(
                  '${student['hsc_batch'] ?? ''} • ${student['college_name'] ?? ''}',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTime(seconds),
                style: TextStyle(
                  color: isBreak ? Colors.amber : Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                isBreak ? 'বিরতিতে' : 'পড়ছে',
                style: TextStyle(
                  color: isBreak
                      ? Colors.amber.withOpacity(0.7)
                      : Colors.green.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── ENDED SCREEN ─────────────────────────────────────────
  Widget _buildEndedScreen() {
    final hours = _studySeconds ~/ 3600;
    final mins = (_studySeconds % 3600) ~/ 60;

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green.withOpacity(0.15),
                  border: Border.all(
                      color: Colors.green.withOpacity(0.4), width: 2),
                ),
                child: const Center(
                  child: Text('🎉', style: TextStyle(fontSize: 48)),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'সেশন শেষ!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('চমৎকার কাজ করেছো!',
                  style: TextStyle(color: Colors.white54, fontSize: 15)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  children: [
                    _statRow('⏱️ মোট পড়া', _formatTime(_studySeconds)),
                    _statRow('☕ ব্রেক নিয়েছো', '$_breaksUsed/$_maxBreaks'),
                    _statRow(
                        '📚 ফলাফল',
                        hours > 0
                            ? '$hours ঘণ্টা $mins মিনিট'
                            : '$mins মিনিট'),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.home),
                      label: const Text('হোমে যাও'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _state = TimerState.idle;
                          _studySeconds = 0;
                          _breakSeconds = 0;
                          _breaksUsed = 0;
                          _sessionId = null;
                          _activeStudents = [];
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('আবার শুরু'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back, color: Colors.white54),
        ),
        const SizedBox(width: 12),
        const Text(
          'Focus Timer',
          style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
