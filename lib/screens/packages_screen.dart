import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});
  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  List<Map<String, dynamic>> _packages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/public/packages'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() =>
            _packages = List<Map<String, dynamic>>.from(data['packages'] ?? []));
      }
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
        title: const Text('প্ল্যান বেছে নাও',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _packages.isEmpty
              ? const Center(
                  child: Text('কোনো প্ল্যান নেই',
                      style: TextStyle(color: Colors.white38)))
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
        .where((f) => f.trim().isNotEmpty)
        .toList();
    final hasVideo = (pkg['youtube_url'] ?? '').isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPremium
              ? [
                  const Color(0xFF2A2010),
                  const Color(0xFF1A1A2E),
                ]
              : [
                  const Color(0xFF0D1520),
                  const Color(0xFF1A1A2E),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPremium
              ? Colors.amber.withOpacity(0.5)
              : Colors.blue.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isPremium ? Colors.amber : Colors.blue).withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isPremium
                    ? [Colors.amber.withOpacity(0.2), Colors.transparent]
                    : [Colors.blue.withOpacity(0.15), Colors.transparent],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Text(
                  isPremium ? '⭐' : '🆓',
                  style: const TextStyle(fontSize: 32),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pkg['name'] ?? '',
                        style: TextStyle(
                          color: isPremium ? Colors.amber : Colors.blue,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if ((pkg['price'] ?? '').isNotEmpty)
                        Text(
                          pkg['price'],
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 14),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((pkg['description'] ?? '').isNotEmpty) ...[
                  Text(
                    pkg['description'],
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                ],
                // Features
                if (features.isNotEmpty) ...[
                  ...features.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color:
                                  isPremium ? Colors.amber : Colors.blue,
                              size: 16,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(f,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13)),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                ],
                // YouTube embed button
                if (hasVideo) ...[
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri.tryParse(pkg['youtube_url']);
                      if (uri != null) await launchUrl(uri);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.red.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.play_circle_filled,
                              color: Colors.red, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ভিডিও দেখো',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                                Text('YouTube এ ডিটেইলস',
                                    style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new,
                              color: Colors.white38, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // CTA
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isPremium
                        ? () {
                            // Contact for premium
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF1E1E2E),
                                title: const Text('প্রিমিয়াম নিতে',
                                    style:
                                        TextStyle(color: Colors.white)),
                                content: const Text(
                                  'অ্যাডমিনের সাথে যোগাযোগ করো।\nতোমার ফোন নম্বর দিলে অ্যাক্সেস দেওয়া হবে।',
                                  style:
                                      TextStyle(color: Colors.white70),
                                ),
                                actions: [
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber),
                                    child: const Text('ঠিক আছে',
                                        style: TextStyle(
                                            color: Colors.black)),
                                  ),
                                ],
                              ),
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isPremium ? Colors.amber : Colors.blue,
                      disabledBackgroundColor:
                          Colors.blue.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isPremium ? 'প্রিমিয়াম নাও' : 'বিনামূল্যে শুরু করো',
                      style: TextStyle(
                        color:
                            isPremium ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
