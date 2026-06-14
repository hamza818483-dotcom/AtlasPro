import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../services/offline_service.dart';
import 'page_access_gate.dart';

class PdfViewerScreen extends StatefulWidget {
  final int pdfId;
  final String title;
  final String r2Url;
  final int chapterId;

  const PdfViewerScreen({
    super.key,
    required this.pdfId,
    required this.title,
    required this.r2Url,
    required this.chapterId,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PDFViewController? _pdfCtrl;
  int _currentPage = 1;
  int _totalPages = 0;
  final Set<int> _selectedPages = {};
  bool _showCheckboxes = false;
  bool _isDownloading = false;
  bool _isCached = false;
  bool _loading = true;
  bool _loadError = false;
  bool _pageBlocked = false;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  Future<void> _initPdf() async {
    setState(() { _loading = true; _loadError = false; });
    final cached = await OfflineService.getCachedPdfPath(widget.pdfId);
    if (cached != null) {
      setState(() { _isCached = true; _localPath = cached; _loading = false; });
      return;
    }
    await _downloadToTemp();
  }

  Future<void> _downloadToTemp() async {
    try {
      final res = await http.get(Uri.parse(widget.r2Url));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/temp_${widget.pdfId}.pdf');
      await file.writeAsBytes(res.bodyBytes);
      setState(() { _localPath = file.path; _loading = false; });
    } catch (e) {
      setState(() { _loadError = true; _loading = false; });
    }
  }

  Future<void> _onPageChanged(int? page, int? total) async {
    if (page == null) return;
    final newPage = page + 1;
    if (newPage == _currentPage) return;
    final allowed = await checkAndRecordPageAccess(context, widget.pdfId, newPage);
    if (!allowed) {
      _pdfCtrl?.setPage(_currentPage - 1);
      setState(() => _pageBlocked = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _pageBlocked = false);
      });
      return;
    }
    setState(() { _currentPage = newPage; _pageBlocked = false; });
  }

  Future<void> _downloadPdf() async {
    setState(() => _isDownloading = true);
    final path = await OfflineService.downloadAndCachePdf(
        widget.pdfId, widget.r2Url, widget.title);
    setState(() {
      _isDownloading = false;
      _isCached = path != null;
      if (path != null) _localPath = path;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path != null ? '✅ অফলাইনে সেভ হয়েছে!' : '❌ ডাউনলোড ব্যর্থ'),
      backgroundColor: path != null ? Colors.green : Colors.red,
    ));
  }

  void _togglePageSelect(int page) {
    setState(() {
      if (_selectedPages.contains(page)) {
        _selectedPages.remove(page);
      } else {
        if (_selectedPages.length >= AppConstants.maxExamPages) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('সর্বোচ্চ ${AppConstants.maxExamPages}টি পৃষ্ঠা'),
            backgroundColor: Colors.orange,
          ));
          return;
        }
        _selectedPages.add(page);
      }
    });
  }

  void _showExamTypeDialog({bool selectedOnly = false}) {
    final pages = selectedOnly && _selectedPages.isNotEmpty
        ? (_selectedPages.toList()..sort())
        : [_currentPage];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(
              selectedOnly ? '${pages.length}টি পৃষ্ঠার পরীক্ষা' : 'পৃষ্ঠা $_currentPage এর পরীক্ষা',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text('MCQ ধরন বেছে নাও',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 20),
            ...[
              ('standard', '📝 Standard MCQ', 'সাধারণ বহুনির্বাচনী', Colors.blue),
              ('true_false', '✅ True / False', 'সত্য বা মিথ্যা', Colors.green),
              ('hard', '🔥 Hard / Analytical', 'কঠিন বিশ্লেষণমূলক', Colors.red),
            ].map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/exam', extra: {
                    'pdf_id': widget.pdfId,
                    'page_numbers': pages,
                    'chapter_id': widget.chapterId,
                    'pdf_title': widget.title,
                    'mcq_type': t.$1,
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: t.$4.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.$4.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Text(t.$2, style: TextStyle(color: t.$4, fontWeight: FontWeight.bold, fontSize: 14)),
                      const Spacer(),
                      Text(t.$3, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_ios, color: t.$4, size: 14),
                    ],
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: Column(
        children: [
          _buildHeader(),
          if (_pageBlocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.red.withOpacity(0.15),
              child: const Text('🔒 আজকের লিমিট শেষ।',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center),
            ),
          if (_selectedPages.isNotEmpty) _buildSelectedBar(),
          Expanded(child: _buildBody()),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('PDF লোড হচ্ছে...', style: TextStyle(color: Colors.white54)),
        ],
      ));
    }
    if (_loadError || _localPath == null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 56),
          const SizedBox(height: 12),
          const Text('PDF লোড হয়নি', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _initPdf,
            icon: const Icon(Icons.refresh),
            label: const Text('আবার চেষ্টা করো'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
          ),
        ],
      ));
    }
    return PDFView(
      filePath: _localPath!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
      onRender: (pages) => setState(() => _totalPages = pages ?? 0),
      onPageChanged: _onPageChanged,
      onViewCreated: (ctrl) => setState(() => _pdfCtrl = ctrl),
      onError: (e) => setState(() => _loadError = true),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppTheme.bgColor,
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
            Expanded(
              child: Text(widget.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Text('$_currentPage / $_totalPages',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            const SizedBox(width: 4),
            const PageRemainingBadge(),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(_showCheckboxes ? Icons.check_box : Icons.check_box_outline_blank,
                  color: _showCheckboxes ? AppTheme.primaryColor : Colors.white54, size: 20),
              onPressed: () => setState(() => _showCheckboxes = !_showCheckboxes),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
            IconButton(
              icon: _isDownloading
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_isCached ? Icons.download_done : Icons.download_outlined,
                      color: _isCached ? Colors.green : Colors.white54, size: 20),
              onPressed: _isDownloading || _isCached ? null : _downloadPdf,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedBar() {
    final sorted = _selectedPages.toList()..sort();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.12),
        border: Border(bottom: BorderSide(color: AppTheme.primaryColor.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text('${_selectedPages.length}/${AppConstants.maxExamPages} — পৃষ্ঠা: $sorted',
              style: TextStyle(color: AppTheme.primaryColor, fontSize: 11))),
          GestureDetector(
            onTap: () => setState(() => _selectedPages.clear()),
            child: const Text('বাদ দাও', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => _showExamTypeDialog(selectedOnly: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('পরীক্ষা দাও', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_showCheckboxes)
              GestureDetector(
                onTap: () => _togglePageSelect(_currentPage),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedPages.contains(_currentPage)
                        ? AppTheme.primaryColor.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _selectedPages.contains(_currentPage)
                        ? AppTheme.primaryColor : Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Icon(_selectedPages.contains(_currentPage) ? Icons.check_box : Icons.check_box_outline_blank,
                          color: _selectedPages.contains(_currentPage) ? AppTheme.primaryColor : Colors.white54,
                          size: 16),
                      const SizedBox(width: 4),
                      Text('পৃষ্ঠা $_currentPage',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: GestureDetector(
                onTap: () => _showExamTypeDialog(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppTheme.primaryColor, AppTheme.accentColor]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.4),
                      blurRadius: 16, offset: const Offset(0, 4),
                    )],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('⚡', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      const Text('এক্সাম দাও',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(width: 8),
                      Text('(পৃষ্ঠা $_currentPage)',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
}
