import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

enum McqType { standard, trueFalse, hard }

extension McqTypeExt on McqType {
  String get label => ['Standard', 'True/False', 'Hard'][index];
  String get key => ['standard', 'true_false', 'hard'][index];
  IconData get icon => [Icons.quiz, Icons.check_circle, Icons.whatshot][index];
  Color get color => [Colors.blue, Colors.green, Colors.red][index];
}

class AdminMcqScreen extends StatefulWidget {
  const AdminMcqScreen({super.key});
  @override
  State<AdminMcqScreen> createState() => _AdminMcqScreenState();
}

class _AdminMcqScreenState extends State<AdminMcqScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _pdfs = [];
  Map<String, dynamic>? _selectedPdf;
  List<Map<String, dynamic>> _mcqs = [];
  Map<String, Map<String, dynamic>> _typeSettings = {};
  bool _loading = false;
  bool _mcqLoading = false;
  McqType _activeType = McqType.standard;

  // Prompts
  final Map<McqType, TextEditingController> _promptCtrls = {
    McqType.standard: TextEditingController(),
    McqType.trueFalse: TextEditingController(),
    McqType.hard: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      setState(() => _activeType = McqType.values[_tabCtrl.index]);
      if (_selectedPdf != null) _loadMcqs();
    });
    _loadPdfs();
    _initDefaultPrompts();
  }

  void _initDefaultPrompts() {
    _promptCtrls[McqType.standard]!.text =
        'Generate 10 multiple choice questions from the following page content. Each question should have 4 options (A, B, C, D) with one correct answer. Include a brief explanation for the correct answer. Format as JSON array.';
    _promptCtrls[McqType.trueFalse]!.text =
        'Generate 10 true/false questions from the following page content. Each question should clearly state a fact that is either true or false. Include explanation. Format as JSON array.';
    _promptCtrls[McqType.hard]!.text =
        'Generate 10 challenging higher-order thinking questions from the following page content. Questions should require analysis, evaluation, or application. 4 options each. Format as JSON array.';
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    for (final c in _promptCtrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadPdfs() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/pdfs/all'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _pdfs = List<Map<String, dynamic>>.from(data['pdfs'] ?? []);
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMcqs() async {
    if (_selectedPdf == null) return;
    setState(() => _mcqLoading = true);
    try {
      final token = await AuthService.getToken();
      final pdfId = _selectedPdf!['id'];
      final res = await http.get(
        Uri.parse(
            '${AppConstants.workerBaseUrl}/api/admin/mcq?pdf_id=$pdfId&type=${_activeType.key}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _mcqs = List<Map<String, dynamic>>.from(data['mcqs'] ?? []);
          _typeSettings[_activeType.key] = data['settings'] ?? {};
          _mcqLoading = false;
        });
      }
    } catch (_) {
      setState(() => _mcqLoading = false);
    }
  }

  Future<void> _toggleType(McqType type, bool enabled) async {
    if (_selectedPdf == null) return;
    final token = await AuthService.getToken();
    await http.put(
      Uri.parse(
          '${AppConstants.workerBaseUrl}/api/admin/mcq/settings'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'pdf_id': _selectedPdf!['id'],
        'type': type.key,
        'enabled': enabled,
        'prompt': _promptCtrls[type]!.text,
      }),
    );
    _loadMcqs();
  }

  Future<void> _generateMcqs(int pageNum) async {
    if (_selectedPdf == null) return;
    final token = await AuthService.getToken();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: Color(0xFF1E1E2E),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generating MCQs via AI...',
                    style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/mcq/generate'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'pdf_id': _selectedPdf!['id'],
          'page_number': pageNum,
          'type': _activeType.key,
          'prompt': _promptCtrls[_activeType]!.text,
        }),
      );
      if (mounted) Navigator.pop(context);
      if (res.statusCode == 200) {
        _loadMcqs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('MCQs generated successfully!'),
              backgroundColor: Colors.green,
            ),
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

  Future<void> _uploadCsv(int? pageNum) async {
    if (_selectedPdf == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final token = await AuthService.getToken();
    final uri = Uri.parse('${AppConstants.workerBaseUrl}/api/admin/mcq/csv');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['pdf_id'] = _selectedPdf!['id'].toString();
    request.fields['type'] = _activeType.key;
    if (pageNum != null) request.fields['page_number'] = pageNum.toString();
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      file.bytes!,
      filename: file.name,
    ));
    final streamedRes = await request.send();
    if (streamedRes.statusCode == 200 || streamedRes.statusCode == 201) {
      _loadMcqs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('CSV imported!'),
              backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _showAddMcqDialog([Map<String, dynamic>? existing]) async {
    final qCtrl = TextEditingController(text: existing?['question'] ?? '');
    final aCtrl = TextEditingController(text: existing?['option_a'] ?? '');
    final bCtrl = TextEditingController(text: existing?['option_b'] ?? '');
    final cCtrl = TextEditingController(text: existing?['option_c'] ?? '');
    final dCtrl = TextEditingController(text: existing?['option_d'] ?? '');
    final expCtrl =
        TextEditingController(text: existing?['explanation'] ?? '');
    final pageCtrl = TextEditingController(
        text: existing?['page_number']?.toString() ?? '1');
    String correct = existing?['correct_answer'] ?? 'A';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            existing != null ? 'Edit MCQ' : 'Add MCQ',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tf(qCtrl, 'Question', maxLines: 3),
                const SizedBox(height: 8),
                _tf(aCtrl, 'Option A'),
                const SizedBox(height: 6),
                _tf(bCtrl, 'Option B'),
                const SizedBox(height: 6),
                _tf(cCtrl, 'Option C'),
                const SizedBox(height: 6),
                _tf(dCtrl, 'Option D'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Correct: ',
                        style: TextStyle(color: Colors.white70)),
                    ...['A', 'B', 'C', 'D'].map((opt) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: GestureDetector(
                            onTap: () => setSt(() => correct = opt),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: correct == opt
                                    ? Colors.green
                                    : Colors.white12,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(opt,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                _tf(expCtrl, 'Explanation', maxLines: 2),
                const SizedBox(height: 6),
                _tf(pageCtrl, 'Page Number',
                    keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (qCtrl.text.trim().isEmpty) return;
                final token = await AuthService.getToken();
                final url = existing != null
                    ? '${AppConstants.workerBaseUrl}/api/admin/mcq/${existing['id']}'
                    : '${AppConstants.workerBaseUrl}/api/admin/mcq';
                final method = existing != null ? 'PUT' : 'POST';
                final req = http.Request(method, Uri.parse(url));
                req.headers['Authorization'] = 'Bearer $token';
                req.headers['Content-Type'] = 'application/json';
                req.body = jsonEncode({
                  'pdf_id': _selectedPdf!['id'],
                  'type': _activeType.key,
                  'question': qCtrl.text.trim(),
                  'option_a': aCtrl.text.trim(),
                  'option_b': bCtrl.text.trim(),
                  'option_c': cCtrl.text.trim(),
                  'option_d': dCtrl.text.trim(),
                  'correct_answer': correct,
                  'explanation': expCtrl.text.trim(),
                  'page_number': int.tryParse(pageCtrl.text) ?? 1,
                });
                final streamedRes = await req.send();
                if (streamedRes.statusCode == 200 ||
                    streamedRes.statusCode == 201) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                }
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == true) _loadMcqs();
  }

  Future<void> _deleteMcq(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Delete MCQ?',
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
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
      Uri.parse('${AppConstants.workerBaseUrl}/api/admin/mcq/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    _loadMcqs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: Row(
        children: [
          // PDF List sidebar
          Container(
            width: 200,
            decoration: const BoxDecoration(
              color: Color(0xFF12121F),
              border: Border(right: BorderSide(color: Color(0xFF2A2A3E))),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  child: const Text('Select PDF',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _pdfs.length,
                          itemBuilder: (ctx, i) {
                            final pdf = _pdfs[i];
                            final isSelected =
                                _selectedPdf?['id'] == pdf['id'];
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor:
                                  AppTheme.primaryColor.withOpacity(0.1),
                              leading: const Icon(Icons.picture_as_pdf,
                                  color: Colors.red, size: 18),
                              title: Text(
                                pdf['title'] ?? '',
                                style: TextStyle(
                                  color:
                                      isSelected ? AppTheme.primaryColor : Colors.white70,
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                pdf['chapter_name'] ?? '',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 10),
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedPdf = pdf;
                                  _mcqs = [];
                                });
                                _loadMcqs();
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          // Main content
          Expanded(
            child: _selectedPdf == null
                ? const Center(
                    child: Text('Select a PDF to manage MCQs',
                        style: TextStyle(color: Colors.white38)))
                : Column(
                    children: [
                      _buildMcqHeader(),
                      TabBar(
                        controller: _tabCtrl,
                        tabs: McqType.values
                            .map((t) => Tab(
                                  icon: Icon(t.icon, size: 16),
                                  text: t.label,
                                ))
                            .toList(),
                        labelColor: AppTheme.primaryColor,
                        unselectedLabelColor: Colors.white38,
                        indicatorColor: AppTheme.primaryColor,
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabCtrl,
                          children: McqType.values
                              .map((t) => _buildTypeTab(t))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMcqHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A3E))),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedPdf?['title'] ?? '',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton.icon(
            onPressed: () => _showAddMcqDialog(),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add MCQ', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
          ),
          TextButton.icon(
            onPressed: () => _uploadCsv(null),
            icon: const Icon(Icons.upload_file, size: 14),
            label: const Text('CSV', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeTab(McqType type) {
    final settings = _typeSettings[type.key] ?? {};
    final enabled = settings['enabled'] as bool? ?? true;
    final filteredMcqs =
        _mcqs.where((m) => m['type'] == type.key).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type settings card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: type.color.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(type.icon, color: type.color, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${type.label} Type',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Switch(
                      value: enabled,
                      activeColor: type.color,
                      onChanged: (val) => _toggleType(type, val),
                    ),
                    Text(
                      enabled ? 'ON' : 'OFF',
                      style: TextStyle(
                        color: enabled ? type.color : Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('AI Prompt:',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                TextField(
                  controller: _promptCtrls[type],
                  maxLines: 4,
                  style:
                      const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.04),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: type.color),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _generateMcqs(1),
                      icon: const Icon(Icons.auto_awesome, size: 14),
                      label:
                          const Text('Generate', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: type.color.withOpacity(0.8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _toggleType(type, enabled),
                      icon: const Icon(Icons.save, size: 14),
                      label:
                          const Text('Save Prompt', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // MCQ list
          Text(
            'MCQs (${filteredMcqs.length})',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_mcqLoading)
            const Center(child: CircularProgressIndicator())
          else if (filteredMcqs.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No MCQs yet. Generate or add manually.',
                    style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            ...filteredMcqs
                .asMap()
                .entries
                .map((e) => _buildMcqCard(e.key + 1, e.value)),
        ],
      ),
    );
  }

  Widget _buildMcqCard(int num, Map<String, dynamic> mcq) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Q$num',
                  style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Page ${mcq['page_number'] ?? '-'}',
                style:
                    const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue, size: 16),
                onPressed: () => _showAddMcqDialog(mcq),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                onPressed: () => _deleteMcq(mcq['id']),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mcq['question'] ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 6),
          ...['A', 'B', 'C', 'D'].map((opt) {
            final key = 'option_${opt.toLowerCase()}';
            final isCorrect = mcq['correct_answer'] == opt;
            return Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? Colors.green
                          : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        opt,
                        style: TextStyle(
                          color: isCorrect ? Colors.white : Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      mcq[key] ?? '',
                      style: TextStyle(
                        color: isCorrect ? Colors.green.shade300 : Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if ((mcq['explanation'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '💡 ${mcq['explanation']}',
                style:
                    const TextStyle(color: Colors.amber, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tf(TextEditingController ctrl, String hint,
      {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primaryColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}
