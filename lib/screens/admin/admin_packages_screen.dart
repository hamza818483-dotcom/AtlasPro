import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

class AdminPackagesScreen extends StatefulWidget {
  const AdminPackagesScreen({super.key});
  @override
  State<AdminPackagesScreen> createState() => _AdminPackagesScreenState();
}

class _AdminPackagesScreenState extends State<AdminPackagesScreen> {
  List<Map<String, dynamic>> _packages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/packages'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _packages =
            List<Map<String, dynamic>>.from(data['packages'] ?? []));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _showPackageDialog([Map<String, dynamic>? existing]) async {
    final nameCtrl =
        TextEditingController(text: existing?['name'] ?? '');
    final priceCtrl =
        TextEditingController(text: existing?['price']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description'] ?? '');
    final videoCtrl =
        TextEditingController(text: existing?['youtube_url'] ?? '');
    final featuresCtrl =
        TextEditingController(text: existing?['features'] ?? '');
    String type = existing?['type'] ?? 'premium';

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            existing != null ? 'Edit Package' : 'Add Package',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Type selector
                Row(
                  children: ['free', 'premium'].map((t) {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setSt(() => type = t),
                        child: Container(
                          margin: EdgeInsets.only(right: t == 'free' ? 4 : 0),
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: type == t
                                ? (t == 'premium'
                                    ? Colors.amber.withOpacity(0.2)
                                    : Colors.blue.withOpacity(0.2))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: type == t
                                  ? (t == 'premium'
                                      ? Colors.amber
                                      : Colors.blue)
                                  : Colors.white12,
                            ),
                          ),
                          child: Text(
                            t == 'premium' ? '⭐ Premium' : '🆓 Free',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: type == t
                                  ? (t == 'premium'
                                      ? Colors.amber
                                      : Colors.blue)
                                  : Colors.white38,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                _tf(nameCtrl, 'Package Name'),
                const SizedBox(height: 8),
                _tf(priceCtrl, 'Price (e.g. ৳499/month)',
                    keyboardType: TextInputType.text),
                const SizedBox(height: 8),
                _tf(descCtrl, 'Description', maxLines: 3),
                const SizedBox(height: 8),
                _tf(videoCtrl, 'YouTube Video URL (optional)'),
                const SizedBox(height: 8),
                _tf(featuresCtrl, 'Features (one per line)', maxLines: 4),
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
                if (nameCtrl.text.trim().isEmpty) return;
                final token = await AuthService.getToken();
                final url = existing != null
                    ? '${AppConstants.workerBaseUrl}/api/admin/packages/${existing['id']}'
                    : '${AppConstants.workerBaseUrl}/api/admin/packages';
                final method = existing != null ? 'PUT' : 'POST';
                final req = http.Request(method, Uri.parse(url));
                req.headers['Authorization'] = 'Bearer $token';
                req.headers['Content-Type'] = 'application/json';
                req.body = jsonEncode({
                  'name': nameCtrl.text.trim(),
                  'price': priceCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'youtube_url': videoCtrl.text.trim(),
                  'features': featuresCtrl.text.trim(),
                  'type': type,
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
    if (result == true) _loadPackages();
  }

  Future<void> _deletePackage(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('Delete Package?',
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
      Uri.parse('${AppConstants.workerBaseUrl}/api/admin/packages/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );
    _loadPackages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPackageDialog(),
        backgroundColor: AppTheme.primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('Add Package'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _packages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.workspace_premium_outlined,
                          color: Colors.white24, size: 64),
                      const SizedBox(height: 16),
                      const Text('No packages yet',
                          style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _showPackageDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Package'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _packages.length,
                  itemBuilder: (ctx, i) => _buildPackageCard(_packages[i]),
                ),
    );
  }

  Widget _buildPackageCard(Map<String, dynamic> pkg) {
    final isPremium = pkg['type'] == 'premium';
    final features = (pkg['features'] ?? '')
        .toString()
        .split('\n')
        .where((f) => f.isNotEmpty)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPremium
              ? [
                  Colors.amber.withOpacity(0.15),
                  Colors.orange.withOpacity(0.05),
                ]
              : [
                  Colors.blue.withOpacity(0.1),
                  Colors.blue.withOpacity(0.03),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPremium
              ? Colors.amber.withOpacity(0.3)
              : Colors.blue.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isPremium ? '⭐ ' : '🆓 ',
                  style: const TextStyle(fontSize: 20),
                ),
                Expanded(
                  child: Text(
                    pkg['name'] ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  pkg['price'] ?? '',
                  style: TextStyle(
                    color: isPremium ? Colors.amber : Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
                  onPressed: () => _showPackageDialog(pkg),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                  onPressed: () => _deletePackage(pkg['id']),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
            if ((pkg['description'] ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                pkg['description'],
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ],
            if (features.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...features.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: isPremium ? Colors.amber : Colors.blue,
                            size: 14),
                        const SizedBox(width: 6),
                        Text(f,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  )),
            ],
            if ((pkg['youtube_url'] ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.play_circle_outline,
                      color: Colors.red, size: 16),
                  const SizedBox(width: 4),
                  const Text('Video attached',
                      style: TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tf(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
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
