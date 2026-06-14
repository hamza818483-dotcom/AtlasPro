import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic> _globalSettings = {};
  bool _loading = true;
  String _searchQuery = '';
  String _filterType = 'all'; // all, free, premium
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final results = await Future.wait([
        http.get(
          Uri.parse('${AppConstants.workerBaseUrl}/api/admin/users'),
          headers: {'Authorization': 'Bearer $token'},
        ),
        http.get(
          Uri.parse('${AppConstants.workerBaseUrl}/api/admin/settings/limits'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ]);
      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body);
        setState(() {
          _users = List<Map<String, dynamic>>.from(data['users'] ?? []);
        });
      }
      if (results[1].statusCode == 200) {
        setState(() {
          _globalSettings = jsonDecode(results[1].body)['settings'] ?? {};
        });
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateUserAccess(Map<String, dynamic> user, String accessType) async {
    final token = await AuthService.getToken();
    final res = await http.put(
      Uri.parse('${AppConstants.workerBaseUrl}/api/admin/users/${user['id']}/access'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'access_type': accessType}),
    );
    if (res.statusCode == 200) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['name']} → $accessType'),
            backgroundColor: accessType == 'premium' ? Colors.amber : Colors.blue,
          ),
        );
      }
    }
  }

  Future<void> _updateUserPageLimit(Map<String, dynamic> user, int limit) async {
    final token = await AuthService.getToken();
    await http.put(
      Uri.parse('${AppConstants.workerBaseUrl}/api/admin/users/${user['id']}/limit'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'daily_page_limit': limit}),
    );
    _loadData();
  }

  Future<void> _updateGlobalLimits(
      int freeLimit, int premiumLimit) async {
    final token = await AuthService.getToken();
    await http.put(
      Uri.parse('${AppConstants.workerBaseUrl}/api/admin/settings/limits'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'free_daily_limit': freeLimit,
        'premium_daily_limit': premiumLimit,
      }),
    );
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Global limits updated!'),
            backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _showGlobalSettingsDialog() async {
    final freeCtrl = TextEditingController(
        text: (_globalSettings['free_daily_limit'] ?? 5).toString());
    final premiumCtrl = TextEditingController(
        text: (_globalSettings['premium_daily_limit'] ?? 100).toString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Global Page Limits',
            style:
                TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSettingsRow('Free Users (pages/day)', freeCtrl, Colors.blue),
            const SizedBox(height: 12),
            _buildSettingsRow(
                'Premium Users (pages/day)', premiumCtrl, Colors.amber),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final f = int.tryParse(freeCtrl.text) ?? 5;
              final p = int.tryParse(premiumCtrl.text) ?? 100;
              Navigator.pop(ctx);
              await _updateGlobalLimits(f, p);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUserDetailDialog(Map<String, dynamic> user) async {
    final limitCtrl = TextEditingController(
        text: (user['daily_page_limit'] ?? 5).toString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
              backgroundImage: user['profile_pic'] != null
                  ? NetworkImage(user['profile_pic'])
                  : null,
              child: user['profile_pic'] == null
                  ? Text(
                      (user['name'] ?? 'U')[0].toUpperCase(),
                      style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user['name'] ?? '',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    user['phone'] ?? '',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow('Father', user['father_name']),
              _infoRow('Mother', user['mother_name']),
              _infoRow('HSC Batch', user['hsc_batch']),
              _infoRow('College', user['college_name']),
              _infoRow('SSC GPA', user['ssc_gpa']?.toString()),
              _infoRow('HSC GPA', user['hsc_gpa']?.toString()),
              _infoRow('Status', user['access_type']?.toString().toUpperCase()),
              _infoRow('Pages Today',
                  '${user['pages_used_today'] ?? 0}/${user['daily_page_limit'] ?? 5}'),
              const Divider(color: Colors.white12),
              const Text('Custom Page Limit:',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: limitCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _updateUserAccess(user, 'free');
                      },
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue)),
                      child: const Text('Set Free'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _updateUserAccess(user, 'premium');
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber),
                      child: const Text('Set Premium',
                          style: TextStyle(color: Colors.black)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final limit = int.tryParse(limitCtrl.text) ?? 5;
                    Navigator.pop(ctx);
                    _updateUserPageLimit(user, limit);
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor),
                  child: const Text('Save Custom Limit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((u) {
      final matchSearch = _searchQuery.isEmpty ||
          (u['name'] ?? '').toLowerCase().contains(_searchQuery) ||
          (u['phone'] ?? '').contains(_searchQuery);
      final matchFilter = _filterType == 'all' ||
          (u['access_type'] ?? 'free') == _filterType;
      return matchSearch && matchFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? const Center(
                        child: Text('No users found',
                            style: TextStyle(color: Colors.white38)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredUsers.length,
                        itemBuilder: (ctx, i) =>
                            _buildUserCard(_filteredUsers[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A3E))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search by name or phone...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showGlobalSettingsDialog,
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Limits', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Total: ${_users.length} | ',
                style:
                    const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              Text(
                'Premium: ${_users.where((u) => u['access_type'] == 'premium').length} | ',
                style:
                    const TextStyle(color: Colors.amber, fontSize: 12),
              ),
              Text(
                'Free: ${_users.where((u) => u['access_type'] != 'premium').length}',
                style:
                    const TextStyle(color: Colors.blue, fontSize: 12),
              ),
              const Spacer(),
              ...[
                ('all', 'All', Colors.white54),
                ('free', 'Free', Colors.blue),
                ('premium', 'Premium', Colors.amber),
              ].map((f) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: GestureDetector(
                      onTap: () => setState(() => _filterType = f.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _filterType == f.$1
                              ? f.$3.withOpacity(0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _filterType == f.$1
                                ? f.$3
                                : Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Text(f.$2,
                            style: TextStyle(
                                color: _filterType == f.$1
                                    ? f.$3
                                    : Colors.white38,
                                fontSize: 11)),
                      ),
                    ),
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final isPremium = user['access_type'] == 'premium';
    final pagesUsed = user['pages_used_today'] ?? 0;
    final pageLimit = user['daily_page_limit'] ?? 5;
    final progress = pageLimit > 0 ? pagesUsed / pageLimit : 0.0;

    return GestureDetector(
      onTap: () => _showUserDetailDialog(user),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPremium
                ? Colors.amber.withOpacity(0.3)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isPremium
                  ? Colors.amber.withOpacity(0.2)
                  : AppTheme.primaryColor.withOpacity(0.15),
              backgroundImage: user['profile_pic'] != null
                  ? NetworkImage(user['profile_pic'])
                  : null,
              child: user['profile_pic'] == null
                  ? Text(
                      (user['name'] ?? 'U')[0].toUpperCase(),
                      style: TextStyle(
                        color: isPremium
                            ? Colors.amber
                            : AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user['name'] ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      if (isPremium)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('⭐ PREMIUM',
                              style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  Text(
                    user['phone'] ?? '',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation(
                              progress > 0.8 ? Colors.red : Colors.green,
                            ),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$pagesUsed/$pageLimit pages',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                Text(
                  user['hsc_batch'] ?? '',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
                const Icon(Icons.chevron_right,
                    color: Colors.white24, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsRow(
      String label, TextEditingController ctrl, Color color) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(color: color, fontSize: 13)),
        ),
        SizedBox(
          width: 80,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              filled: true,
              fillColor: color.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: color),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: color.withOpacity(0.3)),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
