import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

const _mcqTypes = [
  {'key': 'standard', 'label': 'Standard', 'icon': '📝', 'color': Colors.blue},
  {'key': 'true_false', 'label': 'True/False', 'icon': '✅', 'color': Colors.green},
  {'key': 'hard', 'label': 'Hard', 'icon': '🔥', 'color': Colors.red},
];

class AdminPdfPagesScreen extends StatefulWidget {
  final int pdfId;
  final String pdfTitle;
  final int pageCount;

  const AdminPdfPagesScreen({
    super.key,
    required this.pdfId,
    required this.pdfTitle,
    required this.pageCount,
  });

  @override
  State<AdminPdfPagesScreen> createState() => _AdminPdfPagesScreenState();
}

class _AdminPdfPagesScreenState extends State<AdminPdfPagesScreen> {
  int? _selectedPage;
  String _selectedType = 'standard';
  List<Map<String, dynamic>> _mcqs = [];
  Map<String, Map<String, dynamic>> _pageTypeSettings = {};
  bool _mcqLoading = false;
  bool _generating = false;
  int _generateProgress = 0;

  // Page MCQ counts cache
  Map<String, int> _mcqCounts = {}; // key: "pageNum_type"

  @override
  void initState() {
    super.initState();
    _loadPageCounts();
  }

  Future<void> _loadPageCounts() async {
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse(
            '${AppConstants.workerBaseUrl}/api/admin/mcq/counts?pdf_id=${widget.pdfId}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final counts = data['counts'] as Map<String, dynamic>? ?? {};
        setState(() {
          _mcqCounts = counts.map((k, v) => MapEntry(k, v as int));
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMcqs(int page) async {
    setState(() {
      _mcqLoading = true;
      _mcqs = [];
    });
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse(
            '${AppConstants.workerBaseUrl}/api/admin/mcq'
            '?pdf_id=${widget.pdfId}&page_number=$page&type=$_selectedType'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _mcqs = List<Map<String, dynamic>>.from(data['mcqs'] ?? []);

          // Load type settings
          final settings =
              data['settings'] as Map<String, dynamic>? ?? {};
          _pageTypeSettings['${page}_$_selectedType'] = settings;
        });
      }
    } catch (_) {}
    setState(() => _mcqLoading = false);
  }

  Future<void> _generateMcqs(int page) async {
    setState(() {
      _generating = true;
      _generateProgress = 0;
    });
    try {
      final token = await AuthService.getToken();
      final res = await http.post(
        Uri.parse(
            '${AppConstants.workerBaseUrl}/api/admin/mcq/generate'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'pdf_id': widget.pdfId,
          'page_number': page,
          'type': _selectedType,
        }),
      );
      if (res.statusCode == 200) {
        await _loadMcqs(page);
        await _loadPageCounts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ MCQ Generate সফল!'),
            backgroundColor: Colors.green,
          ));
        }
      } else {
        final body = jsonDecode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(body['message'] ?? '❌ Generate ব্যর্থ'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
    setState(() => _generating = false);
  }

  Future<void> _importCsv(int page) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    try {
      final token = await AuthService.getToken();
      final csvContent = utf8.decode(file.bytes!);
      final lines = csvContent
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();

      // Skip header row if present
      final startIdx =
          lines.isNotEmpty && lines[0].toLowerCase().contains('question')
              ? 1
              : 0;

      int imported = 0;
      for (int i = startIdx; i < lines.length; i++) {
        final cols = _parseCsvLine(lines[i]);
        if (cols.length < 6) continue;
        final body = {
          'pdf_id': widget.pdfId,
          'page_number': page,
          'type': _selectedType,
          'question': cols[0],
          'option_a': cols[1],
          'option_b': cols[2],
          'option_c': cols.length > 3 ? cols[3] : '',
          'option_d': cols.length > 4 ? cols[4] : '',
          'correct_answer':
              cols.length > 5 ? cols[5].trim().toUpperCase() : 'A',
          'explanation': cols.length > 6 ? cols[6] : '',
        };
        final res = await http.post(
          Uri.parse(
              '${AppConstants.workerBaseUrl}/api/admin/mcq'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode(body),
        );
        if (res.statusCode == 200 || res.statusCode == 201) imported++;
      }

      await _loadMcqs(page);
      await _loadPageCounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('✅ $imported টি MCQ import সফল!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('CSV Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    bool inQuotes = false;
    final current = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    result.add(current.toString());
    return result;
  }

  Future<void> _toggleTypeEnabled(int page, bool enabled) async {
    try {
      final token = await AuthService.getToken();
      await http.put(
        Uri.parse(
            '${AppConstants.workerBaseUrl}/api/admin/mcq/settings'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'pdf_id': widget.pdfId,
          'page_number': page,
          'type': _selectedType,
          'enabled': enabled,
        }),
      );
      await _loadMcqs(page);
    } catch (_) {}
  }

  Future<void> _showAddEditMcqDialog(int page,
      [Map<String, dynamic>? existing]) async {
    final qCtrl =
        TextEditingController(text: existing?['question'] ?? '');
    final aCtrl =
        TextEditingController(text: existing?['option_a'] ?? '');
    final bCtrl =
        TextEditingController(text: existing?['option_b'] ?? '');
    final cCtrl =
        TextEditingController(text: existing?['option_c'] ?? '');
    final dCtrl =
        TextEditingController(text: existing?['option_d'] ?? '');
    final expCtrl =
        TextEditingController(text: existing?['explanation'] ?? '');
    String correctAnswer =
        existing?['correct_answer'] ?? 'A';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => Dialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                  existing != null ? '✏️ MCQ Edit' : '➕ নতুন MCQ',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 16),
              _dlgField(qCtrl, 'প্রশ্ন (Question)', maxLines: 3),
              const SizedBox(height: 10),
              _dlgField(aCtrl, 'ক) Option A'),
              const SizedBox(height: 8),
              _dlgField(bCtrl, 'খ) Option B'),
              const SizedBox(height: 8),
              _dlgField(cCtrl, 'গ) Option C'),
              const SizedBox(height: 8),
              _dlgField(dCtrl, 'ঘ) Option D'),
              const SizedBox(height: 12),
              const Text('সঠিক উত্তর:',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              Row(children: ['A', 'B', 'C', 'D'].map((opt) {
                final isSelected = correctAnswer == opt;
                final bangla = ['ক', 'খ', 'গ', 'ঘ'][
                    ['A', 'B', 'C', 'D'].indexOf(opt)];
                return GestureDetector(
                  onTap: () =>
                      setSt(() => correctAnswer = opt),
                  child: AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 8),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? Colors.green
                          : Colors.white.withOpacity(0.08),
                      border: Border.all(
                          color: isSelected
                              ? Colors.green
                              : Colors.white24),
                    ),
                    child: Center(
                      child: Text(bangla,
                          style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white54,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList()),
              const SizedBox(height: 10),
              _dlgField(expCtrl, 'ব্যাখ্যা (Explanation)',
                  maxLines: 2),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(ctx2, false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white38,
                        side: const BorderSide(
                            color: Colors.white24)),
                    child: const Text('বাতিল'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (qCtrl.text.trim().isEmpty ||
                          aCtrl.text.trim().isEmpty ||
                          bCtrl.text.trim().isEmpty) return;
                      final token =
                          await AuthService.getToken();
                      final body = {
                        'pdf_id': widget.pdfId,
                        'page_number': page,
                        'type': _selectedType,
                        'question': qCtrl.text.trim(),
                        'option_a': aCtrl.text.trim(),
                        'option_b': bCtrl.text.trim(),
                        'option_c': cCtrl.text.trim(),
                        'option_d': dCtrl.text.trim(),
                        'correct_answer': correctAnswer,
                        'explanation': expCtrl.text.trim(),
                      };
                      final url = existing != null
                          ? '${AppConstants.workerBaseUrl}/api/admin/mcq/${existing['id']}'
                          : '${AppConstants.workerBaseUrl}/api/admin/mcq';
                      final method = existing != null
                          ? 'PUT'
                          : 'POST';
                      final req = http.Request(
                          method, Uri.parse(url));
                      req.headers['Authorization'] =
                          'Bearer $token';
                      req.headers['Content-Type'] =
                          'application/json';
                      req.body = jsonEncode(body);
                      final r = await req.send();
                      if ((r.statusCode == 200 ||
                              r.statusCode == 201) &&
                          ctx2.mounted) {
                        Navigator.pop(ctx2, true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppTheme.primaryColor),
                    child: Text(
                        existing != null ? 'Update' : 'Save'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (result == true) {
      await _loadMcqs(page);
      await _loadPageCounts();
    }
  }

  Future<void> _deleteMcq(int mcqId, int page) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: const Text('MCQ মুছবে?',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('না')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('হ্যাঁ'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final token = await AuthService.getToken();
    await http.delete(
      Uri.parse(
          '${AppConstants.workerBaseUrl}/api/admin/mcq/$mcqId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    await _loadMcqs(page);
    await _loadPageCounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121F),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('পেজ ও MCQ ম্যানেজ',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          Text(widget.pdfTitle,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ]),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white54, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _selectedPage == null
          ? _buildPageGrid()
          : _buildMcqPanel(_selectedPage!),
    );
  }

  Widget _buildPageGrid() {
    return Column(children: [
      // Type selector
      Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF12121F),
        child: Row(children: _mcqTypes.map((t) {
          final isActive = _selectedType == t['key'];
          final color = t['color'] as Color;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedType = t['key'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? color.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? color
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Column(children: [
                  Text(t['icon'] as String,
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(t['label'] as String,
                      style: TextStyle(
                          color: isActive ? color : Colors.white54,
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal)),
                ]),
              ),
            ),
          );
        }).toList()),
      ),

      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Text('পেজ সিলেক্ট করো',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('${widget.pageCount} পেজ',
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11)),
        ]),
      ),

      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: widget.pageCount,
          itemBuilder: (_, i) {
            final pageNum = i + 1;
            final count =
                _mcqCounts['${pageNum}_$_selectedType'] ?? 0;
            final hasM = count > 0;
            return GestureDetector(
              onTap: () async {
                setState(() => _selectedPage = pageNum);
                await _loadMcqs(pageNum);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: hasM
                      ? AppTheme.primaryColor.withOpacity(0.15)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasM
                        ? AppTheme.primaryColor.withOpacity(0.4)
                        : Colors.white.withOpacity(0.08),
                  ),
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text('$pageNum',
                      style: TextStyle(
                          color: hasM
                              ? Colors.white
                              : Colors.white38,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  if (hasM)
                    Text('$count MCQ',
                        style: TextStyle(
                            color:
                                AppTheme.primaryColor,
                            fontSize: 9)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildMcqPanel(int page) {
    final typeInfo = _mcqTypes
        .firstWhere((t) => t['key'] == _selectedType);
    final settingKey = '${page}_$_selectedType';
    final settings = _pageTypeSettings[settingKey] ?? {};
    final isEnabled = settings['enabled'] != false;

    return Column(children: [
      // Panel header
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        color: const Color(0xFF12121F),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _selectedPage = null),
            child: const Row(children: [
              Icon(Icons.arrow_back_ios_new,
                  color: Colors.white54, size: 14),
              SizedBox(width: 4),
              Text('পেজ লিস্ট',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 12),
          Text('${typeInfo['icon']} পেজ $page · ${typeInfo['label']}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const Spacer(),
          // Enable/disable toggle
          Row(children: [
            Text(isEnabled ? 'চালু' : 'বন্ধ',
                style: TextStyle(
                    color: isEnabled ? Colors.green : Colors.red,
                    fontSize: 11)),
            const SizedBox(width: 6),
            Switch(
              value: isEnabled,
              onChanged: (v) => _toggleTypeEnabled(page, v),
              activeColor: Colors.green,
              materialTapTargetSize:
                  MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
        ]),
      ),

      // Action buttons
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        color: const Color(0xFF0D0D1A),
        child: Row(children: [
          _topBtn('➕ MCQ যোগ',
              () => _showAddEditMcqDialog(page),
              AppTheme.primaryColor),
          const SizedBox(width: 8),
          _topBtn('📥 CSV Import',
              () => _importCsv(page), Colors.teal),
          const SizedBox(width: 8),
          _topBtn(
            _generating
                ? '⏳ $_generateProgress%'
                : '🤖 AI Generate',
            _generating ? null : () => _generateMcqs(page),
            Colors.purple,
          ),
        ]),
      ),

      if (!isEnabled)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 8),
          color: Colors.red.withOpacity(0.1),
          child: const Text(
            '⚠️ এই টাইপ বন্ধ আছে। User দেখতে পাবে না।',
            style: TextStyle(color: Colors.red, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),

      // MCQ list
      Expanded(
        child: _mcqLoading
            ? const Center(child: CircularProgressIndicator())
            : _mcqs.isEmpty
                ? _buildEmptyState(page)
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _mcqs.length,
                    itemBuilder: (_, i) =>
                        _buildMcqCard(_mcqs[i], i, page),
                  ),
      ),
    ]);
  }

  Widget _buildEmptyState(int page) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📭', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        const Text('এই পেজে কোনো MCQ নেই',
            style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ElevatedButton.icon(
            onPressed: () => _showAddEditMcqDialog(page),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Manual Add'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _generating ? null : () => _generateMcqs(page),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('AI Generate'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple),
          ),
        ]),
      ]),
    );
  }

  Widget _buildMcqCard(Map<String, dynamic> mcq, int idx, int page) {
    final correctAns = mcq['correct_answer'] as String? ?? 'A';
    final banglaMap = {'A': 'ক', 'B': 'খ', 'C': 'গ', 'D': 'ঘ'};

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Q${idx + 1}',
                  style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Text(
                'সঠিক: ${banglaMap[correctAns] ?? correctAns}',
                style: const TextStyle(
                    color: Colors.green, fontSize: 11)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.edit,
                  color: Colors.blue, size: 16),
              onPressed: () =>
                  _showAddEditMcqDialog(page, mcq),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
            IconButton(
              icon: const Icon(Icons.delete,
                  color: Colors.red, size: 16),
              onPressed: () => _deleteMcq(mcq['id'], page),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(mcq['question'] ?? '',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4)),
            const SizedBox(height: 8),
            ...['A', 'B', 'C', 'D'].map((opt) {
              final key = 'option_${opt.toLowerCase()}';
              final text = (mcq[key] ?? '') as String;
              if (text.isEmpty) return const SizedBox.shrink();
              final isCorrect = opt == correctAns;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCorrect
                          ? Colors.green.withOpacity(0.2)
                          : Colors.transparent,
                      border: Border.all(
                          color: isCorrect
                              ? Colors.green
                              : Colors.white24),
                    ),
                    child: Center(
                      child: Text(banglaMap[opt] ?? opt,
                          style: TextStyle(
                              color: isCorrect
                                  ? Colors.green
                                  : Colors.white38,
                              fontSize: 10,
                              fontWeight:
                                  FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            color: isCorrect
                                ? Colors.green
                                : Colors.white60,
                            fontSize: 12)),
                  ),
                ]),
              );
            }),
            if ((mcq['explanation'] ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('💡 ${mcq['explanation']}',
                  style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _topBtn(String label, VoidCallback? onTap, Color color) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: onTap == null
                ? Colors.white.withOpacity(0.04)
                : color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: onTap == null
                  ? Colors.white12
                  : color.withOpacity(0.4),
            ),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: onTap == null ? Colors.white24 : color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _dlgField(TextEditingController ctrl, String hint,
      {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      ),
    );
  }
}
