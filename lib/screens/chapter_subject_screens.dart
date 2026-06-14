// ─── subject_list_screen.dart ─────────────────────────────
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/offline_service.dart';

class SubjectListScreen extends StatefulWidget {
  final int subjectId;
  final String subjectName;
  const SubjectListScreen(
      {super.key, required this.subjectId, required this.subjectName});
  @override
  State<SubjectListScreen> createState() => _SubjectListScreenState();
}

class _SubjectListScreenState extends State<SubjectListScreen> {
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
        final chapters =
            List<Map<String, dynamic>>.from(data['chapters'] ?? []);
        await OfflineService.cacheChapters(widget.subjectId, chapters);
        setState(() => _chapters = chapters);
      }
    } catch (_) {
      // Offline fallback
      final cached = await OfflineService.getCachedChapters(widget.subjectId);
      setState(() => _chapters = cached);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        backgroundColor: AppTheme.bgColor,
        title: Text(widget.subjectName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chapters.isEmpty
              ? const Center(
                  child: Text('কোনো অধ্যায় নেই',
                      style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _chapters.length,
                  itemBuilder: (ctx, i) => _buildChapterCard(_chapters[i], i),
                ),
    );
  }

  Widget _buildChapterCard(Map<String, dynamic> chapter, int index) {
    return GestureDetector(
      onTap: () => context.push('/chapters/${chapter['id']}',
          extra: {'subject_name': widget.subjectName,
                  'chapter_name': chapter['name']}),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
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
                      fontWeight: FontWeight.bold,
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

// ─── chapter_list_screen.dart ─────────────────────────────
class ChapterListScreen extends StatefulWidget {
  final int subjectId;
  final String subjectName;
  const ChapterListScreen(
      {super.key, required this.subjectId, required this.subjectName});
  @override
  State<ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends State<ChapterListScreen> {
  List<Map<String, dynamic>> _pdfs = [];
  String _chapterName = '';
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
            '${AppConstants.workerBaseUrl}/api/pdfs?chapter_id=${widget.subjectId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _pdfs = List<Map<String, dynamic>>.from(data['pdfs'] ?? []);
          _chapterName = data['chapter_name'] ?? widget.subjectName;
        });
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
        title: Text(_chapterName.isNotEmpty ? _chapterName : widget.subjectName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pdfs.isEmpty
              ? const Center(
                  child: Text('কোনো PDF নেই',
                      style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pdfs.length,
                  itemBuilder: (ctx, i) => _buildPdfCard(_pdfs[i]),
                ),
    );
  }

  Widget _buildPdfCard(Map<String, dynamic> pdf) {
    return FutureBuilder<bool>(
      future: OfflineService.isPdfCached(pdf['id']),
      builder: (ctx, snap) {
        final cached = snap.data ?? false;
        return GestureDetector(
          onTap: () => context.push('/pdf/${pdf['id']}', extra: {
            'title': pdf['title'],
            'r2_url': pdf['r2_url'],
            'chapter_id': widget.subjectId,
          }),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf,
                      color: Colors.red, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pdf['title'] ?? '',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Text('${pdf['page_count'] ?? 0} পৃষ্ঠা',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
                if (cached)
                  const Icon(Icons.download_done,
                      color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white24, size: 14),
              ],
            ),
          ),
        );
      },
    );
  }
}
