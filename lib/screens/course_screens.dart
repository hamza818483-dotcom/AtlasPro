// course_list_screen.dart + course_detail_screen.dart
// AtlasPro Batch 14 — Complete

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';

// ─── COURSE LIST SCREEN ───────────────────────────────────
class CourseListScreen extends StatefulWidget {
  const CourseListScreen({super.key});
  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen> {
  List<Map<String, dynamic>> _subjects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/subjects'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _subjects =
            List<Map<String, dynamic>>.from(data['subjects'] ?? []));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        backgroundColor: AppTheme.bgColor,
        title: const Text('সকল কোর্স',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _subjects.isEmpty
              ? const Center(
                  child: Text('কোনো কোর্স নেই',
                      style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _subjects.length,
                  itemBuilder: (ctx, i) => _buildCard(_subjects[i], i),
                ),
    );
  }

  Widget _buildCard(Map<String, dynamic> sub, int index) {
    final colors = [
      [const Color(0xFF6C63FF), const Color(0xFF3D35B0)],
      [const Color(0xFF00D4AA), const Color(0xFF00856F)],
      [const Color(0xFFFF6B6B), const Color(0xFFB03535)],
      [const Color(0xFFFFBE0B), const Color(0xFFB08500)],
      [const Color(0xFF3A86FF), const Color(0xFF1A56CC)],
    ];
    final c = colors[index % colors.length];

    return GestureDetector(
      onTap: () => context.push('/course/${sub['id']}',
          extra: {'subject': sub}),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c[0].withOpacity(0.2), const Color(0xFF1A1A2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c[0].withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Text(sub['icon'] ?? '📚', style: const TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sub['name'] ?? '',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  if ((sub['description'] ?? '').isNotEmpty)
                    Text(sub['description'],
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: c[0], size: 16),
          ],
        ),
      ),
    );
  }
}

// ─── COURSE DETAIL SCREEN ─────────────────────────────────
class CourseDetailScreen extends StatefulWidget {
  final int subjectId;
  final Map<String, dynamic> subject;
  const CourseDetailScreen(
      {super.key, required this.subjectId, required this.subject});
  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  List<Map<String, dynamic>> _chapters = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse(
            '${AppConstants.workerBaseUrl}/api/chapters?subject_id=${widget.subjectId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _chapters =
            List<Map<String, dynamic>>.from(data['chapters'] ?? []));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: AppTheme.bgColor,
            iconTheme: const IconThemeData(color: Colors.white),
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
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Text(widget.subject['icon'] ?? '📚',
                          style: const TextStyle(fontSize: 48)),
                      const SizedBox(height: 8),
                      Text(widget.subject['name'] ?? '',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: _loading
                ? const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()))
                : _chapters.isEmpty
                    ? const SliverToBoxAdapter(
                        child: Center(
                            child: Text('কোনো অধ্যায় নেই',
                                style: TextStyle(color: Colors.white38))))
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _buildChapterTile(_chapters[i], i),
                          childCount: _chapters.length,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterTile(Map<String, dynamic> chapter, int index) {
    return GestureDetector(
      onTap: () => context.push('/chapters/${chapter['id']}',
          extra: {
            'subject_name': widget.subject['name'],
            'chapter_name': chapter['name'],
          }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text('${index + 1}',
                    style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(chapter['name'] ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14)),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }
}
