import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/access_service.dart';
import '../widgets/announcement_slideshow.dart';
import '../widgets/owner_flip_card.dart';
import '../widgets/app_sidebar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _subjects = [];
  bool _loading = true;
  bool _isAdmin = false;
  String _userName = '';
  int _remainingPages = 0;
  bool _isPremium = false;

  late AnimationController _atlasCtrl;
  late Animation<Color?> _atlasColor;

  @override
  void initState() {
    super.initState();
    _atlasCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _atlasColor = ColorTween(
      begin: AppTheme.primaryColor,
      end: AppTheme.accentColor,
    ).animate(_atlasCtrl);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _loadData();
  }

  @override
  void dispose() {
    _atlasCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _isAdmin = prefs.getBool('is_admin') ?? false;
    _userName = prefs.getString('user_name') ?? 'Student';

    final remaining = await AccessService.getRemainingPages();
    final premium = await AccessService.isPremium();

    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/subjects'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(data['subjects'] ?? []);
        });
      }
    } catch (_) {}

    setState(() {
      _remainingPages = remaining;
      _isPremium = premium;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      drawer: const AppSidebar(),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primaryColor,
        backgroundColor: const Color(0xFF1A1A2E),
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Announcement slideshow
                  const AnnouncementSlideshow(),
                  const SizedBox(height: 16),
                  // Greeting
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'স্বাগতম, $_userName! 👋',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isPremium
                                    ? Colors.amber.withOpacity(0.15)
                                    : Colors.blue.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _isPremium
                                    ? '⭐ Premium'
                                    : '🆓 Free · $_remainingPages পৃষ্ঠা বাকি',
                                style: TextStyle(
                                  color: _isPremium
                                      ? Colors.amber
                                      : Colors.blue,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (!_isPremium) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => context.push('/packages'),
                                child: Text(
                                  'আপগ্রেড করো →',
                                  style: TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Section label
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text(
                          'বিষয়সমূহ',
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1),
                        ),
                        const Spacer(),
                        if (_isAdmin)
                          GestureDetector(
                            onTap: () => context.push('/admin'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.red.withOpacity(0.3)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.admin_panel_settings,
                                      color: Colors.red, size: 14),
                                  SizedBox(width: 4),
                                  Text('Admin',
                                      style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Subjects
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_subjects.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.library_books_outlined,
                                color: Colors.white24, size: 64),
                            const SizedBox(height: 12),
                            const Text('কোনো বিষয় নেই',
                                style: TextStyle(color: Colors.white38)),
                            if (_isAdmin) ...[
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () => context.push('/admin'),
                                icon: const Icon(Icons.add),
                                label: const Text('বিষয় যোগ করো'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryColor),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.3,
                        ),
                        itemCount: _subjects.length,
                        itemBuilder: (ctx, i) =>
                            _buildSubjectCard(_subjects[i]),
                      ),
                    ),
                  const SizedBox(height: 24),
                  // Quick action buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _quickBtn(
                          '⏱️',
                          'Focus Timer',
                          () => context.push('/focus-timer'),
                          AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 10),
                        _quickBtn(
                          '👤',
                          'প্রোফাইল',
                          () => context.push('/profile'),
                          AppTheme.accentColor,
                        ),
                        const SizedBox(width: 10),
                        _quickBtn(
                          '⭐',
                          'প্ল্যান',
                          () => context.push('/packages'),
                          Colors.amber,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  // Owner flip card
                  const OwnerFlipCard(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppTheme.bgColor,
      elevation: 0,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: AnimatedBuilder(
        animation: _atlasColor,
        builder: (_, __) => ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              _atlasColor.value ?? AppTheme.primaryColor,
              AppTheme.accentColor,
            ],
          ).createShader(bounds),
          child: const Text(
            'ATLAS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 24,
              letterSpacing: 4,
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined,
              color: Colors.white54),
          onPressed: () {},
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => context.push('/profile'),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
              child: Text(
                _userName.isNotEmpty ? _userName[0].toUpperCase() : 'A',
                style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectCard(Map<String, dynamic> subject) {
    final colors = [
      [const Color(0xFF6C63FF), const Color(0xFF3D35B0)],
      [const Color(0xFF00D4AA), const Color(0xFF00856F)],
      [const Color(0xFFFF6B6B), const Color(0xFFB03535)],
      [const Color(0xFFFFBE0B), const Color(0xFFB08500)],
      [const Color(0xFF3A86FF), const Color(0xFF1A56CC)],
      [const Color(0xFFFF006E), const Color(0xFFAA0048)],
    ];
    final idx = _subjects.indexOf(subject) % colors.length;
    final c = colors[idx];

    return GestureDetector(
      onTap: () => context.push('/chapters/${subject['id']}',
          extra: {'subject_name': subject['name']}),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c[0].withOpacity(0.85), c[1]],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: c[0].withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subject['icon'] ?? '📚',
                style: const TextStyle(fontSize: 28),
              ),
              const Spacer(),
              Text(
                subject['name'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.list_alt, color: Colors.white60, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    'অধ্যায় দেখো',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios,
                      color: Colors.white54, size: 12),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickBtn(
      String emoji, String label, VoidCallback onTap, Color color) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
