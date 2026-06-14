// lib/services/auth_service.dart — Final
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _tokenKey = 'session_token';
  static const _adminKey = 'is_admin';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_adminKey) ?? false;
  }

  static Future<void> saveSession({
    required String token,
    required Map<String, dynamic> user,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString('user_name', user['name'] ?? '');
    await prefs.setString('hsc_batch', user['hsc_batch'] ?? '');
    await prefs.setString('college_name', user['college_name'] ?? '');
    await prefs.setString('gender', user['gender'] ?? 'male');
    await prefs.setBool(_adminKey, user['is_admin'] == 1 || user['is_admin'] == true);
    if (user['profile_pic'] != null) {
      await prefs.setString('profile_pic', user['profile_pic']);
    }
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
