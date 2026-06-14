import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../services/offline_service.dart';

class OfflineCacheScreen extends StatefulWidget {
  const OfflineCacheScreen({super.key});
  @override
  State<OfflineCacheScreen> createState() => _OfflineCacheScreenState();
}

class _OfflineCacheScreenState extends State<OfflineCacheScreen> {
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _cachedPdfs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await OfflineService.getCacheStats();
    final pdfs = await OfflineService.getCachedPdfs();
    setState(() {
      _stats = stats;
      _cachedPdfs = pdfs;
      _loading = false;
    });
  }

  Future<void> _deletePdf(int pdfId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('ক্যাশ মুছবে?',
            style: TextStyle(color: Colors.white)),
        content: Text('"$title" অফলাইন কপি মুছে যাবে।',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('না')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('মুছো'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await OfflineService.deleteCachedPdf(pdfId);
    _load();
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('সব মুছবে?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'সব ক্যাশ করা PDF এবং MCQ মুছে যাবে। ইন্টারনেট ছাড়া ব্যবহার করা যাবে না।',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('বাতিল')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('সব মুছো'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await OfflineService.clearAll();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        backgroundColor: AppTheme.bgColor,
        title: const Text('অফলাইন ক্যাশ',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (_cachedPdfs.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('সব মুছো',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatsCard(),
                  const SizedBox(height: 20),
                  const Text(
                    'ক্যাশ করা PDF',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1),
                  ),
                  const SizedBox(height: 10),
                  if (_cachedPdfs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.wifi_off,
                              color: Colors.white24, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'কোনো PDF ক্যাশ নেই',
                            style: TextStyle(color: Colors.white38),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'PDF দেখার সময় ডাউনলোড বাটনে ট্যাপ করো।',
                            style: TextStyle(
                                color: Colors.white24, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ..._cachedPdfs
                        .map((pdf) => _buildPdfCard(pdf)),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.15),
            AppTheme.accentColor.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppTheme.primaryColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('📄', '${_stats['cached_pdfs'] ?? 0}', 'PDF'),
              _statItem('❓', '${_stats['cached_mcqs'] ?? 0}', 'MCQ'),
              _statItem('💾', '${_stats['total_size_mb'] ?? 0} MB', 'স্টোরেজ'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.green, size: 14),
                SizedBox(width: 8),
                Text(
                  'ইন্টারনেট ছাড়াও ক্যাশ করা কন্টেন্ট দেখতে পারবে',
                  style: TextStyle(color: Colors.green, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  Widget _buildPdfCard(Map<String, dynamic> pdf) {
    final cachedAt = pdf['cached_at'] as int?;
    final date = cachedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(cachedAt)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
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
                Text(
                  pdf['title'] ?? 'PDF',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                if (date != null)
                  Text(
                    'ক্যাশ: ${date.day}/${date.month}/${date.year}',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('অফলাইন',
                style: TextStyle(color: Colors.green, fontSize: 10)),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.red, size: 20),
            onPressed: () => _deletePdf(pdf['id'], pdf['title'] ?? 'PDF'),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }
}
