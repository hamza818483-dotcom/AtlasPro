import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import 'auth_service.dart';

class AccessService {
  static const String _keyPagesUsed = 'pages_used_today';
  static const String _keyLastDate = 'pages_date';
  static const String _keyDailyLimit = 'daily_page_limit';
  static const String _keyAccessType = 'access_type';

  /// Check if user can view a page. Returns null if allowed, or error message.
  static Future<String?> checkPageAccess() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Reset counter if new day
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString(_keyLastDate) ?? '';
    if (savedDate != today) {
      prefs.setInt(_keyPagesUsed, 0);
      prefs.setString(_keyLastDate, today);
    }

    final used = prefs.getInt(_keyPagesUsed) ?? 0;
    final limit = prefs.getInt(_keyDailyLimit) ?? 5;

    if (used >= limit) {
      final accessType = prefs.getString(_keyAccessType) ?? 'free';
      if (accessType == 'premium') {
        return '⚠️ আজকের প্রিমিয়াম লিমিট ($limit পৃষ্ঠা) শেষ হয়ে গেছে।';
      }
      return '🔒 আজকের বিনামূল্যে পৃষ্ঠার লিমিট ($limit) শেষ।\n\nপ্রিমিয়াম নিলে আরো বেশি পৃষ্ঠা পড়তে পারবে!';
    }

    return null; // allowed
  }

  /// Record a page view (call after successfully viewing a page)
  static Future<void> recordPageView(int pdfId, int pageNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString(_keyLastDate) ?? '';
    
    if (savedDate != today) {
      prefs.setInt(_keyPagesUsed, 0);
      prefs.setString(_keyLastDate, today);
    }
    
    final used = prefs.getInt(_keyPagesUsed) ?? 0;
    prefs.setInt(_keyPagesUsed, used + 1);

    // Sync to server (fire & forget)
    try {
      final token = await AuthService.getToken();
      await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/page-view'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'pdf_id': pdfId,
          'page_number': pageNumber,
        }),
      );
    } catch (_) {}
  }

  /// Sync user limits from server (call on app start/login)
  static Future<void> syncLimits() async {
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/profile/limits'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        prefs.setInt(_keyDailyLimit, data['daily_page_limit'] ?? 5);
        prefs.setString(_keyAccessType, data['access_type'] ?? 'free');
        prefs.setInt(_keyPagesUsed, data['pages_used_today'] ?? 0);
      }
    } catch (_) {}
  }

  static Future<int> getRemainingPages() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString(_keyLastDate) ?? '';
    if (savedDate != today) return prefs.getInt(_keyDailyLimit) ?? 5;
    final used = prefs.getInt(_keyPagesUsed) ?? 0;
    final limit = prefs.getInt(_keyDailyLimit) ?? 5;
    return (limit - used).clamp(0, limit);
  }

  static Future<bool> isPremium() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccessType) == 'premium';
  }
}
