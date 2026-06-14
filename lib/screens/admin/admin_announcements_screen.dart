import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});
  @override
  State<AdminAnnouncementsScreen> createState() =>
      _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  List<Map<String, dynamic>> _cards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/announcements'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _cards =
            List<Map<String, dynamic>>.from(data['announcements'] ?? []));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showCardDialog([Map<String, dynamic>? existing]) async {
    final titleCtrl = TextEditingController(text: existing?['title'] ?? '');
    final bodyCtrl =
        TextEditingController(text: existing?['body'] ?? '');
    final linkCtrl = TextEditingController(text: existing?['link'] ?? '');
    final emojiCtrl =
        TextEditingController(text: existing?['emoji'] ?? '📢');
    String color = existing?['color'] ?? '#6C63FF';
    bool active = existing?['active'] as bool? ?? true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            existing != null ? 'Edit Card' : 'Add Announcement Card',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tf(titleCtrl, 'Card Title'),
                const SizedBox(height: 8),
                _tf(bodyCtrl, 'Card Body', maxLines: 3),
                const SizedBox(height: 8),
                _tf(linkCtrl, 'Link (optional)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _tf(emojiCtrl, 'Emoji')),
                    const SizedBox(width: 8),
                    // Color picker simplified
                    Column(
                      children: [
                        const Text('Color',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            '#6C63FF',
                            '#FF6B6B',
                            '#4ECDC4',
                            '#FFE66D',
                          ].map((c) {
                            final hex =
                                int.tryParse(c.substring(1), radix: 16) ??
                                    0x6C63FF;
                            return GestureDetector(
                              onTap: () => setSt(() => color = c),
                              child: Container(
                                width: 24,
                                height: 24,
                                margin: const EdgeInsets.only(left: 4),
                                decoration: BoxDecoration(
                                  color:
                                      Color(0xFF000000 | hex),
                                  shape: BoxShape.circle,
                                  border: color == c
                                      ? Border.all(
                                          color: Colors.white, width: 2)
                                      : null,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Switch(
                      value: active,
                      activeColor: AppTheme.primaryColor,
                      onChanged: (v) => setSt(() => active = v),
                    ),
                    Text(
                      active ? 'Active' : 'Inactive',
                      style: TextStyle(
                          color: active ? Colors.green : Colors.white38),
                    ),
                  ],
                ),
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
                if (titleCtrl.text.trim().isEmpty) return;
                final token = await AuthService.getToken();
                final url = existing != null
                    ? '${AppConstants.workerBaseUrl}/api/admin/announcements/${existing['id']}'
                    : '${AppConstants.workerBaseUrl}/api/admin/announcements';
                final method = existing != null ? 'PUT' : 'POST';
                final req = http.Request(method, Uri.parse(url));
                req.headers['Authorization'] = 'Bearer $token';
                req.headers['Content-Type'] = 'application/json';
                req.body = jsonEncode({
                  'title': titleCtrl.text.trim(),
                  'body': bodyCtrl.text.trim(),
                  'link': linkCtrl.text.trim(),
                  'emoji': emojiCtrl.text.trim(),
                  'color': color,
                  'active': active,
                });
                final streamedRes = await req.send();
                if (streamedRes.statusCode == 200 ||
                    streamedRes.statusCode == 201) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == true) _loadCards();
  }

  Future<void> _deleteCard(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Delete Card?',
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
      Uri.parse('${AppConstants.workerBaseUrl}/api/admin/announcements/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    _loadCards();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCardDialog(),
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('Add Card'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.campaign_outlined,
                          color: Colors.white24, size: 64),
                      const SizedBox(height: 16),
                      const Text('No announcement cards',
                          style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _showCardDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Card'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.amber.withOpacity(0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.amber, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Cards slide every 3 seconds on home page. Multiple cards show as slideshow.',
                                style: TextStyle(
                                    color: Colors.amber, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _cards.length,
                        onReorder: (oldI, newI) async {
                          if (newI > oldI) newI--;
                          setState(() {
                            final card = _cards.removeAt(oldI);
                            _cards.insert(newI, card);
                          });
                          // Save order
                          final token = await AuthService.getToken();
                          await http.put(
                            Uri.parse(
                                '${AppConstants.workerBaseUrl}/api/admin/announcements/order'),
                            headers: {
                              'Authorization': 'Bearer $token',
                              'Content-Type': 'application/json',
                            },
                            body: jsonEncode({
                              'order': _cards
                                  .map((c) => c['id'])
                                  .toList(),
                            }),
                          );
                        },
                        itemBuilder: (ctx, i) {
                          final card = _cards[i];
                          final hexStr =
                              (card['color'] ?? '#6C63FF').substring(1);
                          final hexColor = Color(
                              0xFF000000 |
                                  (int.tryParse(hexStr, radix: 16) ??
                                      0x6C63FF));
                          return Container(
                            key: ValueKey(card['id']),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A2E),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: hexColor.withOpacity(0.3)),
                            ),
                            child: ListTile(
                              leading: Text(card['emoji'] ?? '📢',
                                  style: const TextStyle(fontSize: 24)),
                              title: Text(
                                card['title'] ?? '',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    card['body'] ?? '',
                                    style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: card['active'] == true
                                          ? Colors.green.withOpacity(0.2)
                                          : Colors.red.withOpacity(0.2),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      card['active'] == true
                                          ? 'Active'
                                          : 'Inactive',
                                      style: TextStyle(
                                        color: card['active'] == true
                                            ? Colors.green
                                            : Colors.red,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.blue, size: 16),
                                    onPressed: () =>
                                        _showCardDialog(card),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(6),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red, size: 16),
                                    onPressed: () =>
                                        _deleteCard(card['id']),
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(6),
                                  ),
                                  const Icon(Icons.drag_handle,
                                      color: Colors.white24, size: 18),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _tf(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
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
