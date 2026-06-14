import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/subjects'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(data['subjects'] ?? []);
          _loading = false;
        });
      } else {
        setState(() { _error = 'Failed to load'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadChapters(int subjectId) async {
    final token = await AuthService.getToken();
    final res = await http.get(
      Uri.parse('${AppConstants.workerBaseUrl}/api/admin/chapters?subject_id=$subjectId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _chapters[subjectId] = List<Map<String, dynamic>>.from(data['chapters'] ?? []);
      });
    }
  }

  Future<void> _loadPdfs(int chapterId) async {
    final token = await AuthService.getToken();
    final res = await http.get(
      Uri.parse('${AppConstants.workerBaseUrl}/api/admin/pdfs?chapter_id=$chapterId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _pdfs[chapterId] = List<Map<String, dynamic>>.from(data['pdfs'] ?? []);
      });
    }
  }

  Future<void> _showAddSubjectDialog([Map<String, dynamic>? existing]) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final iconCtrl = TextEditingController(text: existing?['icon'] ?? '📚');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildDialog(
        title: existing != null ? 'Edit Subject' : 'Add Subject',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(nameCtrl, 'Subject Name', Icons.book),
            const SizedBox(height: 12),
            _buildTextField(descCtrl, 'Description (optional)', Icons.description),
            const SizedBox(height: 12),
            _buildTextField(iconCtrl, 'Emoji Icon', Icons.emoji_emotions),
          ],
        ),
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
          final streamedRes = await req.send();
          if (streamedRes.statusCode == 200 || streamedRes.statusCode == 201) {
            if (ctx.mounted) Navigator.pop(ctx, true);
          }
        },
      ),
    );
    if (result == true) _loadSubjects();
  }

  Future<void> _showAddChapterDialog(int subjectId, [Map<String, dynamic>? existing]) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final orderCtrl = TextEditingController(text: existing?['order_index']?.toString() ?? '1');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildDialog(
        title: existing != null ? 'Edit Chapter' : 'Add Chapter',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(nameCtrl, 'Chapter Name', Icons.list_alt),
            const SizedBox(height: 12),
            _buildTextField(orderCtrl, 'Order', Icons.sort, TextInputType.number),
          ],
        ),
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
          final streamedRes = await req.send();
          if (streamedRes.statusCode == 200 || streamedRes.statusCode == 201) {
            if (ctx.mounted) Navigator.pop(ctx, true);
          }
        },
      ),
    );
    if (result == true) _loadChapters(subjectId);
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

    // Show upload dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          color: Color(0xFF1E1E2E),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Uploading PDF...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final token = await AuthService.getToken();
      final uri = Uri.parse('${AppConstants.workerBaseUrl}/api/admin/pdfs/upload');
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
      if (streamedRes.statusCode == 200 || streamedRes.statusCode == 201) {
        _loadPdfs(chapterId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('PDF uploaded successfully!'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload failed'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteItem(String type, int id, {int? parentId}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Confirm Delete', style: TextStyle(color: Colors.white)),
        content: Text('Delete this $type?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final token = await AuthService.getToken();
    await http.delete(
      Uri.parse('${AppConstants.workerBaseUrl}/api/admin/${type}s/$id'),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: _loadSubjects, child: const Text('Retry')),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSubjectDialog(),
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('Add Subject'),
      ),
      body: _subjects.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.library_books_outlined,
                      color: Colors.white24, size: 64),
                  const SizedBox(height: 16),
                  const Text('No subjects yet',
                      style: TextStyle(color: Colors.white54)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showAddSubjectDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Subject'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _subjects.length,
              itemBuilder: (ctx, i) => _buildSubjectCard(_subjects[i]),
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
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  subject['icon'] ?? '📚',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            title: Text(
              subject['name'] ?? '',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              subject['description'] ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                  onPressed: () => _showAddSubjectDialog(subject),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                  onPressed: () => _deleteItem('subject', sId),
                ),
                IconButton(
                  icon: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white54,
                  ),
                  onPressed: () async {
                    setState(() {
                      _expandedSubject = isExpanded ? null : sId;
                      _expandedChapter = null;
                    });
                    if (!isExpanded) await _loadChapters(sId);
                  },
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.list_alt,
                          color: Colors.white38, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Chapters (${chapters.length})',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _showAddChapterDialog(sId),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add Chapter',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor),
                      ),
                    ],
                  ),
                  ...chapters.map((ch) => _buildChapterCard(ch, sId)),
                ],
              ),
            ),
          ],
        ],
      ),
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
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_rounded,
                color: Colors.amber, size: 20),
            title: Text(
              chapter['name'] ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 16),
                  onPressed: () =>
                      _showAddChapterDialog(subjectId, chapter),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                  onPressed: () =>
                      _deleteItem('chapter', chId, parentId: subjectId),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                ),
                IconButton(
                  icon: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.white38,
                    size: 18,
                  ),
                  onPressed: () async {
                    setState(() {
                      _expandedChapter = isExpanded ? null : chId;
                    });
                    if (!isExpanded) await _loadPdfs(chId);
                  },
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                ),
              ],
            ),
          ),
          if (isExpanded) ...[
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.picture_as_pdf,
                          color: Colors.white38, size: 14),
                      const SizedBox(width: 6),
                      Text('PDFs (${pdfs.length})',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _uploadPdf(chId),
                        icon: const Icon(Icons.upload_file, size: 14),
                        label: const Text('Upload PDF',
                            style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.green),
                      ),
                    ],
                  ),
                  ...pdfs.map((pdf) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.picture_as_pdf,
                            color: Colors.red, size: 18),
                        title: Text(
                          pdf['title'] ?? '',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        subtitle: Text(
                          '${pdf['page_count'] ?? 0} pages',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete,
                              color: Colors.red, size: 16),
                          onPressed: () =>
                              _deleteItem('pdf', pdf['id'], parentId: chId),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: child,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
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
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint,
    IconData icon, [
    TextInputType? keyboardType,
  ]) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
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
