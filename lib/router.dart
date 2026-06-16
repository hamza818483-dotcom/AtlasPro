// lib/router.dart — FINAL (Batch 14, replaces Batch 12 version)
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/course_screens.dart';           // CourseListScreen + CourseDetailScreen
import 'screens/chapter_subject_screens.dart'; // SubjectListScreen + ChapterListScreen
import 'screens/pdf_viewer_screen.dart';
import 'screens/exam_screen.dart';
import 'screens/exam_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/focus_timer_screen.dart';
import 'screens/packages_screen.dart';
import 'screens/offline_cache_screen.dart';
import 'screens/admin/admin_panel_screen.dart';

Future<bool> _isLoggedIn() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getString('session_token') ?? '').isNotEmpty;
}

Future<bool> _isAdmin() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('is_admin') ?? false;
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) async {
    final path = state.uri.toString();
    final loggedIn = await _isLoggedIn();
    if (loggedIn && path == '/auth') return '/home';
    if (path == '/admin' && !(await _isAdmin())) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/',
        builder: (_, __) => const SplashScreen()),

    GoRoute(path: '/auth',
        builder: (_, __) => const AuthScreen()),

    GoRoute(path: '/home',
        builder: (_, __) => const HomeScreen()),

    GoRoute(path: '/courses',
        builder: (_, __) => const CourseListScreen()),

    GoRoute(
      path: '/course/:id',
      builder: (_, state) {
        final extra = (state.extra as Map<String, dynamic>?) ?? {};
        return CourseDetailScreen(
          subjectId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
          subject: extra['subject'] as Map<String, dynamic>? ?? {},
        );
      },
    ),

    GoRoute(
      path: '/chapters/:id',
      builder: (_, state) {
        final extra = (state.extra as Map<String, dynamic>?) ?? {};
        return ChapterListScreen(
          subjectId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
          subjectName: extra['subject_name'] as String? ?? '',
        );
      },
    ),

    GoRoute(
      path: '/subjects/:id',
      builder: (_, state) {
        final extra = (state.extra as Map<String, dynamic>?) ?? {};
        return SubjectListScreen(
          subjectId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
          subjectName: extra['subject_name'] as String? ?? '',
        );
      },
    ),

    GoRoute(
      path: '/pdf/:id',
      builder: (_, state) {
        final extra = (state.extra as Map<String, dynamic>?) ?? {};
        return PdfViewerScreen(
          pdfId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
          title: extra['title'] as String? ?? 'PDF',
          r2Url: extra['r2_url'] as String? ?? '',
          chapterId: (extra['chapter_id'] as int?) ?? 0,
        );
      },
    ),

    GoRoute(
      path: '/exam',
      builder: (_, state) => ExamScreen(
        params: (state.extra as Map<String, dynamic>?) ?? {},
      ),
    ),

    GoRoute(
      path: '/exam-detail',
      builder: (_, state) => ExamDetailScreen(
        examResult: (state.extra as Map<String, dynamic>?) ?? {},
      ),
    ),

    GoRoute(path: '/profile',
        builder: (_, __) => const ProfileScreen()),

    GoRoute(path: '/focus-timer',
        builder: (_, __) => const FocusTimerScreen()),

    GoRoute(path: '/packages',
        builder: (_, __) => const PackagesScreen()),

    GoRoute(path: '/offline-cache',
        builder: (_, __) => const OfflineCacheScreen()),

    GoRoute(path: '/admin',
        builder: (_, __) => const AdminPanelScreen()),
  ],
  errorBuilder: (context, state) => Scaffold(
    backgroundColor: const Color(0xFF0A0A14),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('❌', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('পৃষ্ঠা পাওয়া যায়নি',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.go('/home'),
            child: const Text('হোমে যাও'),
          ),
        ],
      ),
    ),
  ),
);
