import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import 'admin_subjects_screen.dart';
import 'admin_mcq_screen.dart';
import 'admin_users_screen.dart';
import 'admin_owner_screen.dart';
import 'admin_announcements_screen.dart';
import 'admin_packages_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int? _activeSection; // null = show grid, 0-5 = show section
  Map<String, int> _stats = {};

  final _sections = [
    _Section('📚', 'বিষয়', 'Subject · Chapter · PDF', Colors.blue),
    _Section('📝', 'MCQ', 'প্রশ্ন ব্যবস্থাপনা', Colors.purple),
    _Section('👥', 'শিক্ষার্থী', 'ব্যবহারকারী নিয়ন্ত্রণ', Colors.green),
    _Section('📢', 'ঘোষণা', 'Special Cards', Colors.orange),
    _Section('⭐', 'প্যাকেজ', 'Subscription Plans', Colors.amber),
    _Section('👤', 'Owner', 'প্রোফাইল কার্ড', Colors.pink),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/stats'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _stats = {
            'students': data['students'] ?? 0,
            'exams': data['exams'] ?? 0,
            'pdfs': data['pdfs'] ?? 0,
            'subjects': data['subjects'] ?? 0,
          };
        });
      }
    } catch (_) {}
  }

  Widget _buildScreen(int idx) {
    return switch (idx) {
      0 => const AdminSubjectsScreen(),
      1 => const AdminMcqScreen(),
      2 => const AdminUsersScreen(),
      3 => const AdminAnnouncementsScreen(),
      4 => const AdminPackagesScreen(),
      5 => const AdminOwnerScreen(),
      _ => const SizedBox(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: _activeSection == null
                ? _buildDashboard()
                : Column(children: [
                    _buildSectionHeader(_activeSection!),
                    Expanded(child: _buildScreen(_activeSection!)),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.2),
            AppTheme.bgColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: const Border(
            bottom: BorderSide(color: Color(0xFF2A2A3E), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        ShaderMask(
          shaderCallback: (b) => LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.accentColor])
              .createShader(b),
          child: const Text('ATLAS',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: 3)),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin Panel',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            Text('Full Control Center',
                style: TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
        const Spacer(),
        if (_activeSection != null)
          IconButton(
            icon: const Icon(Icons.grid_view_rounded, color: Colors.white54),
            tooltip: 'Back to Dashboard',
            onPressed: () => setState(() => _activeSection = null),
          ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white38),
          onPressed: () => Navigator.pop(context),
        ),
      ]),
    );
  }

  Widget _buildSectionHeader(int idx) {
    final s = _sections[idx];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: const Color(0xFF12121F),
      child: Row(children: [
        GestureDetector(
          onTap: () => setState(() => _activeSection = null),
          child: const Row(children: [
            Icon(Icons.arrow_back_ios_new, color: Colors.white54, size: 14),
            SizedBox(width: 4),
            Text('Back', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 12),
        Text(s.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        Text(s.label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ]),
    );
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Stats row
        Row(children: [
          _statCard('👥', _stats['students']?.toString() ?? '-', 'শিক্ষার্থী',
              Colors.blue),
          const SizedBox(width: 10),
          _statCard('📝', _stats['exams']?.toString() ?? '-', 'পরীক্ষা',
              Colors.purple),
          const SizedBox(width: 10),
          _statCard('📄', _stats['pdfs']?.toString() ?? '-', 'PDF',
              Colors.green),
          const SizedBox(width: 10),
          _statCard('📚', _stats['subjects']?.toString() ?? '-', 'বিষয়',
              Colors.orange),
        ]),
        const SizedBox(height: 20),

        // Section label
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('ম্যানেজমেন্ট',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
        ),
        const SizedBox(height: 10),

        // Section grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemCount: _sections.length,
          itemBuilder: (_, i) => _sectionBox(i),
        ),
        const SizedBox(height: 20),

        // Quick tips card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppTheme.primaryColor.withOpacity(0.15)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('💡 Quick Guide',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              SizedBox(height: 8),
              Text(
                '① বিষয় → Chapter → PDF Upload করো\n'
                '② MCQ → PDF সিলেক্ট → পেজ সিলেক্ট → MCQ Generate/Add\n'
                '③ ঘোষণা → Special card add করো home-এ দেখাবে',
                style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _statCard(String emoji, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ),
    );
  }

  Widget _sectionBox(int idx) {
    final s = _sections[idx];
    final isActive = _activeSection == idx;
    return GestureDetector(
      onTap: () => setState(() => _activeSection = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive
              ? s.color.withOpacity(0.2)
              : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? s.color.withOpacity(0.6)
                : Colors.white.withOpacity(0.08),
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                      color: s.color.withOpacity(0.25),
                      blurRadius: 12,
                      spreadRadius: 1)
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(s.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(s.label,
                style: TextStyle(
                    color: isActive ? s.color : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(s.sub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 9)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section {
  final String emoji;
  final String label;
  final String sub;
  final Color color;
  const _Section(this.emoji, this.label, this.sub, this.color);
}
