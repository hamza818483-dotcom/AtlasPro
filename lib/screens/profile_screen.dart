import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _examHistory = [];
  bool _loading = true;
  bool _uploading = false;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final results = await Future.wait([
        http.get(
          Uri.parse('${AppConstants.workerBaseUrl}/api/profile'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        http.get(
          Uri.parse('${AppConstants.workerBaseUrl}/api/profile/exam-history'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ]);

      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body);
        setState(() => _profile = data['profile'] ?? {});
        // Save to prefs
        final prefs = await SharedPreferences.getInstance();
        final p = data['profile'] ?? {};
        prefs.setString('user_name', p['name'] ?? '');
        prefs.setString('hsc_batch', p['hsc_batch'] ?? '');
        prefs.setString('college_name', p['college_name'] ?? '');
        prefs.setString('gender', p['gender'] ?? 'male');
        if (p['profile_pic'] != null) {
          prefs.setString('profile_pic', p['profile_pic']);
        }
      }

      if (results[1].statusCode == 200) {
        final data = jsonDecode(results[1].body);
        setState(() => _examHistory =
            List<Map<String, dynamic>>.from(data['history'] ?? []));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final token = await AuthService.getToken();
      final uri =
          Uri.parse('${AppConstants.workerBaseUrl}/api/profile/photo');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        picked.path,
      ));
      final streamedRes = await request.send();
      if (streamedRes.statusCode == 200) {
        final body = await streamedRes.stream.bytesToString();
        final data = jsonDecode(body);
        setState(() => _profile['profile_pic'] = data['url']);
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('profile_pic', data['url']);
      }
    } finally {
      setState(() => _uploading = false);
    }
  }

  Future<void> _startPractice(Map<String, dynamic> exam,
      {bool mistakeOnly = false}) async {
    Navigator.pushNamed(
      context,
      '/exam',
      arguments: {
        'pdf_id': exam['pdf_id'],
        'page_numbers': exam['page_numbers'],
        'mcq_type': exam['mcq_type'],
        'practice_mode': true,
        'mistake_only': mistakeOnly,
        'exam_id': exam['id'],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: _buildInfoCards(),
          ),
          SliverToBoxAdapter(
            child: _buildTabBar(),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildExamHistoryTab(),
                _buildStatsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: AppTheme.bgColor,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryColor.withOpacity(0.3),
                AppTheme.bgColor,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              GestureDetector(
                onTap: _pickAndUploadPhoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppTheme.primaryColor.withOpacity(0.15),
                      backgroundImage: _profile['profile_pic'] != null
                          ? NetworkImage(_profile['profile_pic'])
                          : null,
                      child: _profile['profile_pic'] == null
                          ? Text(
                              (_profile['gender'] ?? 'male') == 'female'
                                  ? '👩'
                                  : '👨',
                              style: const TextStyle(fontSize: 40),
                            )
                          : null,
                    ),
                    if (_uploading)
                      const Positioned.fill(
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.bgColor, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _profile['name'] ?? '',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              Text(
                '${_profile['college_name'] ?? ''} • HSC ${_profile['hsc_batch'] ?? ''}',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _profile['access_type'] == 'premium'
                      ? Colors.amber.withOpacity(0.2)
                      : Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _profile['access_type'] == 'premium'
                      ? '⭐ Premium'
                      : '🆓 Free',
                  style: TextStyle(
                    color: _profile['access_type'] == 'premium'
                        ? Colors.amber
                        : Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCards() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Personal info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ব্যক্তিগত তথ্য',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                const SizedBox(height: 12),
                ...[
                  ('👤 পিতার নাম', _profile['father_name']),
                  ('👤 মাতার নাম', _profile['mother_name']),
                  ('📱 ফোন', _profile['phone']),
                  ('📱 ২য় নম্বর', _profile['secondary_phone']),
                  ('🔗 Facebook/Telegram', _profile['social_link']),
                  ('📊 SSC GPA', _profile['ssc_gpa']?.toString()),
                  ('📊 HSC GPA', _profile['hsc_gpa']?.toString()),
                ]
                    .where((e) => e.$2 != null && e.$2!.isNotEmpty)
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 140,
                                child: Text(e.$1,
                                    style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12)),
                              ),
                              Expanded(
                                child: Text(e.$2!,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12)),
                              ),
                            ],
                          ),
                        )),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Quick stats
          Row(
            children: [
              _quickStat('📝', 'মোট পরীক্ষা',
                  _examHistory.length.toString()),
              const SizedBox(width: 8),
              _quickStat(
                  '✅',
                  'গড় স্কোর',
                  _examHistory.isEmpty
                      ? '-'
                      : '${(_examHistory.map((e) => (e['score'] as num? ?? 0)).reduce((a, b) => a + b) / _examHistory.length).toStringAsFixed(1)}%'),
              const SizedBox(width: 8),
              _quickStat(
                  '📄',
                  'পেজ আজকে',
                  '${_profile['pages_used_today'] ?? 0}/${_profile['daily_page_limit'] ?? 5}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickStat(String emoji, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppTheme.bgColor,
      child: TabBar(
        controller: _tabCtrl,
        tabs: const [
          Tab(icon: Icon(Icons.history, size: 18), text: 'পরীক্ষার ইতিহাস'),
          Tab(icon: Icon(Icons.bar_chart, size: 18), text: 'পরিসংখ্যান'),
        ],
        labelColor: AppTheme.primaryColor,
        unselectedLabelColor: Colors.white38,
        indicatorColor: AppTheme.primaryColor,
      ),
    );
  }

  Widget _buildExamHistoryTab() {
    if (_examHistory.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, color: Colors.white24, size: 56),
            SizedBox(height: 12),
            Text('এখনো কোনো পরীক্ষা দেওনি',
                style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _examHistory.length,
      itemBuilder: (ctx, i) => _buildExamHistoryCard(_examHistory[i]),
    );
  }

  Widget _buildExamHistoryCard(Map<String, dynamic> exam) {
    final score = (exam['score'] as num? ?? 0).toDouble();
    final total = exam['total_questions'] as int? ?? 0;
    final correct = exam['correct_answers'] as int? ?? 0;
    final isGood = score >= 70;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGood
              ? Colors.green.withOpacity(0.2)
              : Colors.red.withOpacity(0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam['subject_name'] ?? 'Subject',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    Text(
                      '${exam['chapter_name'] ?? ''} • পৃষ্ঠা: ${exam['page_numbers'] ?? '-'}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    Text(
                      exam['exam_date'] ?? '',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Score circle
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isGood
                      ? Colors.green.withOpacity(0.15)
                      : Colors.red.withOpacity(0.15),
                  border: Border.all(
                    color: isGood
                        ? Colors.green.withOpacity(0.4)
                        : Colors.red.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${score.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: isGood ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '$correct/$total',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(
                  isGood ? Colors.green : Colors.red),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            children: [
              _actionBtn(
                'বিস্তারিত',
                Icons.info_outline,
                Colors.blue,
                () => _showExamDetail(exam),
              ),
              const SizedBox(width: 6),
              _actionBtn(
                'Practice',
                Icons.replay,
                AppTheme.primaryColor,
                () => _startPractice(exam),
              ),
              const SizedBox(width: 6),
              _actionBtn(
                'ভুলগুলো',
                Icons.error_outline,
                Colors.orange,
                () => _startPractice(exam, mistakeOnly: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  void _showExamDetail(Map<String, dynamic> exam) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final questions =
            List<Map<String, dynamic>>.from(exam['questions'] ?? []);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                exam['subject_name'] ?? 'পরীক্ষার বিস্তারিত',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: questions.isEmpty
                    ? const Center(
                        child: Text('প্রশ্নের বিস্তারিত পাওয়া যায়নি',
                            style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        itemCount: questions.length,
                        itemBuilder: (ctx, i) {
                          final q = questions[i];
                          final isCorrect =
                              q['user_answer'] == q['correct_answer'];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isCorrect
                                  ? Colors.green.withOpacity(0.08)
                                  : Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isCorrect
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.red.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isCorrect
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: isCorrect
                                          ? Colors.green
                                          : Colors.red,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text('Q${i + 1}',
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(q['question'] ?? '',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12)),
                                const SizedBox(height: 4),
                                if (!isCorrect)
                                  Text(
                                    'তোমার উত্তর: ${q['user_answer']} | সঠিক: ${q['correct_answer']}',
                                    style: const TextStyle(
                                        color: Colors.orange,
                                        fontSize: 11),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsTab() {
    if (_examHistory.isEmpty) {
      return const Center(
          child: Text('পরীক্ষা দিলে পরিসংখ্যান দেখা যাবে',
              style: TextStyle(color: Colors.white38)));
    }

    final bySubject = <String, List<double>>{};
    for (final exam in _examHistory) {
      final sub = exam['subject_name'] ?? 'Unknown';
      bySubject.putIfAbsent(sub, () => []);
      bySubject[sub]!.add((exam['score'] as num? ?? 0).toDouble());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('বিষয় অনুযায়ী পারফরম্যান্স',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 12),
        ...bySubject.entries.map((entry) {
          final avg = entry.value.reduce((a, b) => a + b) / entry.value.length;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    Text('${avg.toStringAsFixed(1)}% গড়',
                        style: TextStyle(
                          color: avg >= 70 ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: avg / 100,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(
                      avg >= 70 ? Colors.green : Colors.orange,
                    ),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${entry.value.length}টি পরীক্ষা',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
              ],
            ),
          );
        }),
      ],
    );
  }
}
