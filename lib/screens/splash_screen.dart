import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/access_service.dart';
import '../services/offline_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));

    _scaleAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)));

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 0.7, curve: Curves.easeIn)));

    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)));

    _ctrl.forward();
    _init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 2200)),
      AccessService.syncLimits().catchError((_) {}),
      OfflineService.syncPending().catchError((_) {}),
    ]);

    if (!mounted) return;
    final loggedIn = await AuthService.isLoggedIn();
    context.go(loggedIn ? '/home' : '/auth');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Glow circle
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(_glowAnim.value * 0.5),
                      blurRadius: 60,
                      spreadRadius: 20,
                    ),
                    BoxShadow(
                      color: AppTheme.accentColor.withOpacity(_glowAnim.value * 0.3),
                      blurRadius: 80,
                      spreadRadius: -10,
                    ),
                  ],
                ),
                child: Transform.scale(
                  scale: _scaleAnim.value,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor,
                          AppTheme.accentColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'A',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Opacity(
                opacity: _fadeAnim.value,
                child: ShaderMask(
                  shaderCallback: (b) => LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.accentColor],
                  ).createShader(b),
                  child: const Text(
                    'ATLAS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: _fadeAnim.value,
                child: const Text(
                  'শিক্ষার্থীদের বিশ্বস্ত সঙ্গী',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
              const SizedBox(height: 60),
              Opacity(
                opacity: _glowAnim.value,
                child: SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                    minHeight: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
