import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../services/access_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _loading = false;
  String? _error;
  late TabController _tabCtrl;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  // Login
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Register
  final _nameCtrl = TextEditingController();
  final _fatherCtrl = TextEditingController();
  final _motherCtrl = TextEditingController();
  final _hscBatchCtrl = TextEditingController();
  final _collegeCtrl = TextEditingController();
  final _sscGpaCtrl = TextEditingController();
  final _hscGpaCtrl = TextEditingController();
  final _regPhoneCtrl = TextEditingController();
  final _secPhoneCtrl = TextEditingController();
  final _socialCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  String _gender = 'male';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() =>
        setState(() => _isLogin = _tabCtrl.index == 0));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _phoneCtrl.dispose(); _passCtrl.dispose();
    _nameCtrl.dispose(); _fatherCtrl.dispose(); _motherCtrl.dispose();
    _hscBatchCtrl.dispose(); _collegeCtrl.dispose(); _sscGpaCtrl.dispose();
    _hscGpaCtrl.dispose(); _regPhoneCtrl.dispose(); _secPhoneCtrl.dispose();
    _socialCtrl.dispose(); _regPassCtrl.dispose(); _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_phoneCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'ফোন নম্বর এবং পাসওয়ার্ড দাও');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': _phoneCtrl.text.trim(),
          'password': _passCtrl.text,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('session_token', data['token']);
        await prefs.setString('user_name', data['user']?['name'] ?? '');
        await prefs.setString('hsc_batch', data['user']?['hsc_batch'] ?? '');
        await prefs.setString('college_name', data['user']?['college_name'] ?? '');
        await prefs.setString('gender', data['user']?['gender'] ?? 'male');
        await prefs.setBool('is_admin', data['user']?['is_admin'] == 1);
        if (data['user']?['profile_pic'] != null) {
          await prefs.setString('profile_pic', data['user']['profile_pic']);
        }
        await AccessService.syncLimits();
        if (mounted) context.go('/home');
      } else {
        setState(() => _error = data['error'] ?? 'লগইন ব্যর্থ হয়েছে');
      }
    } catch (e) {
      setState(() => _error = 'সংযোগ ব্যর্থ। আবার চেষ্টা করো।');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _regPhoneCtrl.text.isEmpty ||
        _regPassCtrl.text.isEmpty) {
      setState(() => _error = 'নাম, ফোন ও পাসওয়ার্ড আবশ্যক');
      return;
    }
    if (_regPassCtrl.text != _confirmPassCtrl.text) {
      setState(() => _error = 'পাসওয়ার্ড মিলছে না');
      return;
    }
    if (_regPassCtrl.text.length < 6) {
      setState(() => _error = 'পাসওয়ার্ড কমপক্ষে ৬ অক্ষর');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('${AppConstants.workerBaseUrl}/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameCtrl.text.trim(),
          'father_name': _fatherCtrl.text.trim(),
          'mother_name': _motherCtrl.text.trim(),
          'hsc_batch': _hscBatchCtrl.text.trim(),
          'college_name': _collegeCtrl.text.trim(),
          'ssc_gpa': _sscGpaCtrl.text.trim(),
          'hsc_gpa': _hscGpaCtrl.text.trim(),
          'phone': _regPhoneCtrl.text.trim(),
          'secondary_phone': _secPhoneCtrl.text.trim(),
          'social_link': _socialCtrl.text.trim(),
          'password': _regPassCtrl.text,
          'gender': _gender,
        }),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 201 && data['token'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('session_token', data['token']);
        await prefs.setString('user_name', _nameCtrl.text.trim());
        await prefs.setString('hsc_batch', _hscBatchCtrl.text.trim());
        await prefs.setString('college_name', _collegeCtrl.text.trim());
        await prefs.setString('gender', _gender);
        await prefs.setBool('is_admin', false);
        await AccessService.syncLimits();
        if (mounted) context.go('/home');
      } else {
        setState(() => _error = data['error'] ?? 'রেজিস্ট্রেশন ব্যর্থ');
      }
    } catch (_) {
      setState(() => _error = 'সংযোগ ব্যর্থ। আবার চেষ্টা করো।');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                children: [
                  ShaderMask(
                    shaderCallback: (b) => LinearGradient(
                      colors: [AppTheme.primaryColor, AppTheme.accentColor],
                    ).createShader(b),
                    child: const Text('ATLAS',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6)),
                  ),
                  const SizedBox(height: 4),
                  const Text('শিক্ষার্থীদের জন্য',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            ),
            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabCtrl,
                indicator: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                dividerColor: Colors.transparent,
                tabs: const [Tab(text: 'লগইন'), Tab(text: 'রেজিস্ট্রেশন')],
              ),
            ),
            const SizedBox(height: 8),
            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12))),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [_buildLogin(), _buildRegister()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogin() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _tf(_phoneCtrl, 'ফোন নম্বর', Icons.phone,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 12),
          _tf(_passCtrl, 'পাসওয়ার্ড', Icons.lock,
              obscure: _obscurePass,
              suffixIcon: IconButton(
                icon: Icon(
                    _obscurePass ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white38,
                    size: 18),
                onPressed: () =>
                    setState(() => _obscurePass = !_obscurePass),
              )),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('লগইন করো',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegister() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('ব্যক্তিগত তথ্য'),
          _tf(_nameCtrl, 'পুরো নাম *', Icons.person),
          const SizedBox(height: 10),
          _tf(_fatherCtrl, 'পিতার নাম', Icons.person_outline),
          const SizedBox(height: 10),
          _tf(_motherCtrl, 'মাতার নাম', Icons.person_outline),
          const SizedBox(height: 10),
          // Gender
          Row(
            children: [
              const Text('লিঙ্গ:',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(width: 12),
              ...[('male', '👨 ছেলে'), ('female', '👩 মেয়ে')].map((g) =>
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _gender = g.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _gender == g.$1
                              ? AppTheme.primaryColor.withOpacity(0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _gender == g.$1
                                ? AppTheme.primaryColor
                                : Colors.white24,
                          ),
                        ),
                        child: Text(g.$2,
                            style: TextStyle(
                                color: _gender == g.$1
                                    ? AppTheme.primaryColor
                                    : Colors.white54,
                                fontSize: 13)),
                      ),
                    ),
                  )),
            ],
          ),
          const SizedBox(height: 16),
          _sectionLabel('শিক্ষা তথ্য'),
          _tf(_hscBatchCtrl, 'HSC ব্যাচ (যেমন: 2025)', Icons.calendar_today),
          const SizedBox(height: 10),
          _tf(_collegeCtrl, 'কলেজের নাম', Icons.school),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _tf(_sscGpaCtrl, 'SSC GPA', Icons.grade,
                  keyboardType: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(child: _tf(_hscGpaCtrl, 'HSC GPA', Icons.grade,
                  keyboardType: TextInputType.number)),
            ],
          ),
          const SizedBox(height: 16),
          _sectionLabel('যোগাযোগ'),
          _tf(_regPhoneCtrl, 'ফোন নম্বর *', Icons.phone,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          _tf(_secPhoneCtrl, '২য় ফোন নম্বর', Icons.phone_android,
              keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          _tf(_socialCtrl, 'Facebook/Telegram লিঙ্ক', Icons.link),
          const SizedBox(height: 16),
          _sectionLabel('পাসওয়ার্ড'),
          _tf(_regPassCtrl, 'পাসওয়ার্ড *', Icons.lock,
              obscure: _obscurePass,
              suffixIcon: IconButton(
                icon: Icon(
                    _obscurePass ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white38, size: 18),
                onPressed: () =>
                    setState(() => _obscurePass = !_obscurePass),
              )),
          const SizedBox(height: 10),
          _tf(_confirmPassCtrl, 'পাসওয়ার্ড নিশ্চিত করো *', Icons.lock_outline,
              obscure: _obscureConfirm,
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white38, size: 18),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              )),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _register,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('রেজিস্ট্রেশন করো',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label.toUpperCase(),
          style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5)),
    );
  }

  Widget _tf(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.primaryColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}
