import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import 'admin_pdf_pages_screen.dart';

class AdminSubjectsScreen extends StatefulWidget {
  const AdminSubjectsScreen({super.key});
  @override
  State<AdminSubjectsScreen> createState() => _AdminSubjectsScreenState();
}

class _AdminSubjectsScreenState extends State<AdminSubjectsScreen> {
  List<Map<String, dynamic>> _subjects = [];
  Map<int, List<Map<String, dynamic>>> _chapters = {};
  Map<int, List<Map<String, dynamic>>> _pdfs = {};
  int? _expandedSubject;
  int? _expandedChapter;
  bool _loading = true;
  String? _error;
  Map<int, bool> _ocrLoading = {};

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/subjects'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _subjects =
              List<Map<String, dynamic>>.from(data['subjects'] ?? []);
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'লোড ব্যর্থ (${res.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadChapters(int subjectId) async {
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse(
            '${AppConstants.workerBaseUrl}/api/admin/chapters?subject_id=$subjectId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _chapters[subjectId] =
              List<Map<String, dynamic>>.from(data['chapters'] ?? []);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPdfs(int chapterId) async {
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse(
            '${AppConstants.workerBaseUrl}/api/admin/pdfs?chapter_id=$chapterId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _pdfs[chapterId] =
              List<Map<String, dynamic>>.from(data['pdfs'] ?? []);
        });
      }
    } catch (_) {}
  }

  Future<void> _triggerOcr(int pdfId) async {
    setState(() => _ocrLoading[pdfId] = true);
    try {
      final token = await AuthService.getToken();
      final res = await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/pdfs/$pdfId/ocr'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.statusCode == 200
              ? '✅ OCR Processing শুরু হয়েছে!'
              : '❌ OCR শুরু করা যায়নি'),
          backgroundColor:
              res.statusCode == 200 ? Colors.green.shade700 : Colors.red,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ OCR Error'),
          backgroundColor: Colors.red,
        ));
      }
    }
    setState(() => _ocrLoading[pdfId] = false);
  }

  Future<void> _showAddSubjectDialog([Map<String, dynamic>? existing]) async {
    final nameCtrl =
        TextEditingController(text: existing?['name'] ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description'] ?? '');
    final iconCtrl =
        TextEditingController(text: existing?['icon'] ?? '📚');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildDialog(
        title: existing != null ? 'বিষয় Edit' : 'নতুন বিষয়',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(nameCtrl, 'বিষয়ের নাম', Icons.book),
          const SizedBox(height: 12),
          _field(descCtrl, 'বিবরণ (optional)', Icons.description),
          const SizedBox(height: 12),
          _field(iconCtrl, 'Emoji Icon', Icons.emoji_emotions),
        ]),
        onSave: () async {
          if (nameCtrl.text.trim().isEmpty) return;
          final token = await AuthService.getToken();
          final url = existing != null
              ? '${AppConstants.workerBaseUrl}/api/admin/subjects/${existing['id']}'
              : '${AppConstants.workerBaseUrl}/api/admin/subjects';
          final method = existing != null ? 'PUT' : 'POST';
          final req = http.Request(method, Uri.parse(url));
          req.headers['Authorization'] = 'Bearer $token';
          req.headers['Content-Type'] = 'application/json';
          req.body = jsonEncode({
            'name': nameCtrl.text.trim(),
            'description': descCtrl.text.trim(),
            'icon': iconCtrl.text.trim(),
          });
          final r = await req.send();
          if ((r.statusCode == 200 || r.statusCode == 201) &&
              ctx.mounted) {
            Navigator.pop(ctx, true);
          }
        },
      ),
    );
    if (result == true) _loadSubjects();
  }

  Future<void> _showAddChapterDialog(int subjectId,
      [Map<String, dynamic>? existing]) async {
    final nameCtrl =
        TextEditingController(text: existing?['name'] ?? '');
    final orderCtrl = TextEditingController(
        text: existing?['order_index']?.toString() ?? '1');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildDialog(
        title: existing != null ? 'Chapter Edit' : 'নতুন Chapter',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(nameCtrl, 'Chapter-এর নাম', Icons.list_alt),
          const SizedBox(height: 12),
          _field(orderCtrl, 'ক্রম সংখ্যা', Icons.sort,
              TextInputType.number),
        ]),
        onSave: () async {
          if (nameCtrl.text.trim().isEmpty) return;
          final token = await AuthService.getToken();
          final url = existing != null
              ? '${AppConstants.workerBaseUrl}/api/admin/chapters/${existing['id']}'
              : '${AppConstants.workerBaseUrl}/api/admin/chapters';
          final method = existing != null ? 'PUT' : 'POST';
          final req = http.Request(method, Uri.parse(url));
          req.headers['Authorization'] = 'Bearer $token';
          req.headers['Content-Type'] = 'application/json';
          req.body = jsonEncode({
            'subject_id': subjectId,
            'name': nameCtrl.text.trim(),
            'order_index': int.tryParse(orderCtrl.text) ?? 1,
          });
          final r = await req.send();
          if ((r.statusCode == 200 || r.statusCode == 201) &&
              ctx.mounted) {
            Navigator.pop(ctx, true);
          }
        },
      ),
    );
    if (result == true) _loadChapters(subjectId);
  }

  Future<void> _showEditPdfDialog(Map<String, dynamic> pdf,
      int chapterId) async {
    final titleCtrl =
        TextEditingController(text: pdf['title'] ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildDialog(
        title: 'PDF Edit',
        child: _field(titleCtrl, 'PDF Title', Icons.picture_as_pdf),
        onSave: () async {
          if (titleCtrl.text.trim().isEmpty) return;
          final token = await AuthService.getToken();
          final res = await http.put(
            Uri.parse(
                '${AppConstants.workerBaseUrl}/api/admin/pdfs/${pdf['id']}'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({'title': titleCtrl.text.trim()}),
          );
          if ((res.statusCode == 200 || res.statusCode == 201) &&
              ctx.mounted) {
            Navigator.pop(ctx, true);
          }
        },
      ),
    );
    if (result == true) _loadPdfs(chapterId);
  }

  Future<void> _uploadPdf(int chapterId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _UploadingDialog(),
    );

    try {
      final token = await AuthService.getToken();
      final uri =
          Uri.parse('${AppConstants.workerBaseUrl}/api/admin/pdfs/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['chapter_id'] = chapterId.toString();
      request.fields['title'] = file.name.replaceAll('.pdf', '');
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
      ));
      final streamedRes = await request.send();
      if (mounted) Navigator.pop(context);

      if (streamedRes.statusCode == 200 ||
          streamedRes.statusCode == 201) {
        // Auto-trigger OCR
        final body = await streamedRes.stream.bytesToString();
        try {
          final data = jsonDecode(body);
          final pdfId = data['pdf_id'] ?? data['id'];
          if (pdfId != null) _triggerOcr(pdfId);
        } catch (_) {}

        await _loadPdfs(chapterId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                const Text('✅ PDF upload সফল! OCR processing শুরু...'),
            backgroundColor: Colors.green.shade700,
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('❌ Upload ব্যর্থ'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _deleteItem(String type, int id, {int? parentId}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('মুছে ফেলবে?',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('এই $type মুছে ফেলা হবে। Undo সম্ভব নয়।',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('না, থাকুক',
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('হ্যাঁ, মুছো'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final token = await AuthService.getToken();
    await http.delete(
      Uri.parse(
          '${AppConstants.workerBaseUrl}/api/admin/${type}s/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (type == 'subject') _loadSubjects();
    if (type == 'chapter' && parentId != null) _loadChapters(parentId);
    if (type == 'pdf' && parentId != null) _loadPdfs(parentId);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadSubjects,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor),
          ),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSubjectDialog(),
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('বিষয় যোগ করো'),
      ),
      body: _subjects.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.library_books_outlined,
                      color: Colors.white24, size: 64),
                  const SizedBox(height: 16),
                  const Text('কোনো বিষয় নেই',
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showAddSubjectDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('প্রথম বিষয় যোগ করো'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
              itemCount: _subjects.length,
              itemBuilder: (_, i) => _buildSubjectCard(_subjects[i]),
            ),
    );
  }

  Widget _buildSubjectCard(Map<String, dynamic> subject) {
    final sId = subject['id'] as int;
    final isExpanded = _expandedSubject == sId;
    final chapters = _chapters[sId] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded
              ? AppTheme.primaryColor.withOpacity(0.5)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(subject['icon'] ?? '📚',
                  style: const TextStyle(fontSize: 22)),
            ),
          ),
          title: Text(subject['name'] ?? '',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: subject['description'] != null &&
                  (subject['description'] as String).isNotEmpty
              ? Text(subject['description'],
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11))
              : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _iconBtn(
                Icons.edit,
                Colors.blue,
                () => _showAddSubjectDialog(subject)),
            _iconBtn(Icons.delete, Colors.red,
                () => _deleteItem('subject', sId)),
            _iconBtn(
              isExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              Colors.white38,
              () async {
                setState(() {
                  _expandedSubject = isExpanded ? null : sId;
                  _expandedChapter = null;
                });
                if (!isExpanded) await _loadChapters(sId);
              },
            ),
          ]),
        ),
        if (isExpanded) ...[
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.folder_open, color: Colors.amber, size: 14),
                const SizedBox(width: 6),
                Text('Chapters (${chapters.length})',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
                const Spacer(),
                _textBtn('+ Chapter যোগ',
                    () => _showAddChapterDialog(sId)),
              ]),
              const SizedBox(height: 8),
              ...chapters.map((ch) => _buildChapterCard(ch, sId)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildChapterCard(Map<String, dynamic> chapter, int subjectId) {
    final chId = chapter['id'] as int;
    final isExpanded = _expandedChapter == chId;
    final pdfs = _pdfs[chId] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpanded
              ? Colors.amber.withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(children: [
        ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: const Icon(Icons.folder_rounded,
              color: Colors.amber, size: 20),
          title: Text(chapter['name'] ?? '',
              style:
                  const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text('Order: ${chapter['order_index'] ?? 0}',
              style:
                  const TextStyle(color: Colors.white24, fontSize: 10)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _iconBtn(Icons.edit, Colors.blue,
                () => _showAddChapterDialog(subjectId, chapter), size: 16),
            _iconBtn(Icons.delete, Colors.red,
                () => _deleteItem('chapter', chId, parentId: subjectId),
                size: 16),
            _iconBtn(
              isExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              Colors.white38,
              () async {
                setState(() =>
                    _expandedChapter = isExpanded ? null : chId);
                if (!isExpanded) await _loadPdfs(chId);
              },
              size: 18,
            ),
          ]),
        ),
        if (isExpanded) ...[
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.picture_as_pdf,
                    color: Colors.red, size: 13),
                const SizedBox(width: 6),
                Text('PDFs (${pdfs.length})',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11)),
                const Spacer(),
                _textBtn('📤 Upload PDF', () => _uploadPdf(chId),
                    color: Colors.green),
              ]),
              const SizedBox(height: 8),
              ...pdfs.map((pdf) => _buildPdfCard(pdf, chId)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildPdfCard(Map<String, dynamic> pdf, int chapterId) {
    final pdfId = pdf['id'] as int;
    final pageCount = pdf['page_count'] ?? 0;
    final ocrDone = pdf['ocr_done'] == true || pdf['ocr_done'] == 1;
    final isOcrLoading = _ocrLoading[pdfId] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.picture_as_pdf,
                color: Colors.red, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(pdf['title'] ?? '',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              Text(
                '$pageCount পেজ  •  ${ocrDone ? "✅ OCR Done" : "⏳ OCR Pending"}',
                style: TextStyle(
                    color: ocrDone ? Colors.green : Colors.orange,
                    fontSize: 10),
              ),
            ]),
          ),
          _iconBtn(Icons.edit, Colors.blue,
              () => _showEditPdfDialog(pdf, chapterId), size: 16),
          _iconBtn(Icons.delete, Colors.red,
              () => _deleteItem('pdf', pdfId, parentId: chapterId),
              size: 16),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          // OCR button
          Expanded(
            child: _actionBtn(
              isOcrLoading
                  ? '🔄 OCR চলছে...'
                  : ocrDone
                      ? '🔁 Re-OCR'
                      : '🔍 OCR করো',
              isOcrLoading ? null : () => _triggerOcr(pdfId),
              color: Colors.teal,
            ),
          ),
          const SizedBox(width: 8),
          // Per-page MCQ management
          Expanded(
            flex: 2,
            child: _actionBtn(
              '📝 পেজ ও MCQ ম্যানেজ',
              pageCount == 0
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminPdfPagesScreen(
                            pdfId: pdfId,
                            pdfTitle: pdf['title'] ?? '',
                            pageCount: pageCount,
                          ),
                        ),
                      ),
              color: AppTheme.primaryColor,
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _actionBtn(String label, VoidCallback? onTap, {Color? color}) {
    final c = color ?? AppTheme.primaryColor;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: onTap == null ? Colors.white.withOpacity(0.04) : c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: onTap == null ? Colors.white12 : c.withOpacity(0.35),
          ),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: onTap == null ? Colors.white24 : c,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap,
      {double size = 18}) {
    return IconButton(
      icon: Icon(icon, color: color, size: size),
      onPressed: onTap,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(6),
    );
  }

  Widget _textBtn(String label, VoidCallback onTap, {Color? color}) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
          foregroundColor: color ?? AppTheme.primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildDialog({
    required String title,
    required Widget child,
    required Future<void> Function() onSave,
  }) {
    bool saving = false;
    return StatefulBuilder(
      builder: (context, setSt) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: child,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('বাতিল',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: saving
                ? null
                : () async {
                    setSt(() => saving = true);
                    await onSave();
                    setSt(() => saving = false);
                  },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor),
            child: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2))
                : const Text('সেভ করো'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      [TextInputType? type]) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.primaryColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class _UploadingDialog extends StatelessWidget {
  const _UploadingDialog();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Card(
        color: Color(0xFF1E1E2E),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('PDF আপলোড হচ্ছে...',
                style: TextStyle(color: Colors.white)),
            SizedBox(height: 6),
            Text('একটু অপেক্ষা করো',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
