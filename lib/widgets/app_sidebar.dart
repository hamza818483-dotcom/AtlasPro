import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/access_service.dart';

class AppSidebar extends StatefulWidget {
  const AppSidebar({super.key});
  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  bool _isAdmin = false;
  Map<String, String> _userInfo = {};
  int _remainingPages = 0;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final remaining = await AccessService.getRemainingPages();
    final premium = await AccessService.isPremium();
    setState(() {
      _isAdmin = prefs.getBool('is_admin') ?? false;
      _userInfo = {
        'name': prefs.getString('user_name') ?? 'Student',
        'hsc_batch': prefs.getString('hsc_batch') ?? '',
        'college': prefs.getString('college_name') ?? '',
        'profile_pic': prefs.getString('profile_pic') ?? '',
      };
      _remainingPages = remaining;
      _isPremium = premium;
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text('লগআউট?',
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('না')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('হ্যাঁ'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0D0D1A),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (_isAdmin) ..._buildAdminItems(),
                  const SizedBox(height: 4),
                  _sectionLabel('মেনু'),
                  ..._buildUserItems(),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final picUrl = _userInfo['profile_pic'] ?? '';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.2),
            Colors.transparent,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.primaryColor.withOpacity(0.15),
                backgroundImage:
                    picUrl.isNotEmpty ? NetworkImage(picUrl) : null,
                child: picUrl.isEmpty
                    ? const Text('👤', style: TextStyle(fontSize: 24))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userInfo['name'] ?? '',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'HSC ${_userInfo['hsc_batch'] ?? ''}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    if (_isAdmin)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('🔑 Admin',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Page usage bar
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isPremium ? '⭐ Premium' : '🆓 Free',
                      style: TextStyle(
                        color: _isPremium ? Colors.amber : Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$_remainingPages পৃষ্ঠা বাকি আজ',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAdminItems() {
    return [
      _sectionLabel('Admin'),
      _navItem(Icons.admin_panel_settings_rounded, 'Admin Panel',
          '/admin', color: Colors.red),
    ];
  }

  List<Widget> _buildUserItems() {
    final items = [
      (Icons.home_rounded, 'হোম', '/home'),
      (Icons.person_rounded, 'প্রোফাইল', '/profile'),
      (Icons.timer_rounded, 'Focus Timer', '/focus-timer'),
      (Icons.history_rounded, 'পরীক্ষার ইতিহাস', '/profile'),
      (Icons.workspace_premium_rounded, 'প্ল্যান দেখো', '/packages'),
    ];
    return items
        .map((e) => _navItem(e.$1, e.$2, e.$3))
        .toList();
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, String route,
      {Color? color}) {
    final isActive = GoRouterState.of(context).uri.toString() == route;
    return ListTile(
      dense: true,
      leading: Icon(icon,
          color: isActive
              ? AppTheme.primaryColor
              : (color ?? Colors.white54),
          size: 20),
      title: Text(
        label,
        style: TextStyle(
          color: isActive ? AppTheme.primaryColor : Colors.white70,
          fontWeight:
              isActive ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      tileColor: isActive
          ? AppTheme.primaryColor.withOpacity(0.08)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      onTap: () {
        Navigator.pop(context);
        context.push(route);
      },
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.logout, color: Colors.red, size: 20),
        title: const Text('লগআউট',
            style: TextStyle(color: Colors.red, fontSize: 14)),
        onTap: _logout,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        tileColor: Colors.red.withOpacity(0.06),
      ),
    );
  }
}
