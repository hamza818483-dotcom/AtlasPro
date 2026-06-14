import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

class AdminOwnerScreen extends StatefulWidget {
  const AdminOwnerScreen({super.key});
  @override
  State<AdminOwnerScreen> createState() => _AdminOwnerScreenState();
}

class _AdminOwnerScreenState extends State<AdminOwnerScreen> {
  Map<String, dynamic> _ownerData = {};
  bool _loading = true;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _fbCtrl = TextEditingController();
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _loadOwnerData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _titleCtrl.dispose();
    _bioCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _fbCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOwnerData() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.getToken();
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/owner'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)['owner'] ?? {};
        setState(() {
          _ownerData = data;
          _nameCtrl.text = data['name'] ?? '';
          _titleCtrl.text = data['title'] ?? '';
          _bioCtrl.text = data['bio'] ?? '';
          _emailCtrl.text = data['email'] ?? '';
          _phoneCtrl.text = data['phone'] ?? '';
          _fbCtrl.text = data['facebook'] ?? '';
          _imageUrl = data['image_url'];
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _uploadImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final token = await AuthService.getToken();
    final uri =
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/owner/image');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      file.bytes!,
      filename: file.name,
    ));
    final streamedRes = await request.send();
    if (streamedRes.statusCode == 200) {
      final body = await streamedRes.stream.bytesToString();
      final data = jsonDecode(body);
      setState(() => _imageUrl = data['url']);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final token = await AuthService.getToken();
      final res = await http.put(
        Uri.parse('${AppConstants.workerBaseUrl}/api/admin/owner'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': _nameCtrl.text.trim(),
          'title': _titleCtrl.text.trim(),
          'bio': _bioCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'facebook': _fbCtrl.text.trim(),
          'image_url': _imageUrl,
        }),
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Owner card saved!'),
              backgroundColor: Colors.green),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Preview card
            _buildPreviewCard(),
            const SizedBox(height: 24),
            const Text(
              'Edit Owner Card',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Photo upload
            Center(
              child: GestureDetector(
                onTap: _uploadImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor:
                          AppTheme.primaryColor.withOpacity(0.15),
                      backgroundImage:
                          _imageUrl != null ? NetworkImage(_imageUrl!) : null,
                      child: _imageUrl == null
                          ? Icon(Icons.person,
                              color: AppTheme.primaryColor, size: 40)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _field(_nameCtrl, 'Owner Name', Icons.person),
            const SizedBox(height: 12),
            _field(_titleCtrl, 'Title/Role', Icons.work),
            const SizedBox(height: 12),
            _field(_bioCtrl, 'Bio/Description', Icons.info, maxLines: 4),
            const SizedBox(height: 12),
            _field(_emailCtrl, 'Email', Icons.email),
            const SizedBox(height: 12),
            _field(_phoneCtrl, 'Phone', Icons.phone),
            const SizedBox(height: 12),
            _field(_fbCtrl, 'Facebook Link', Icons.link),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Owner Card',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.2),
            AppTheme.accentColor.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.primaryColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.2),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('PREVIEW',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.6),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 38,
                backgroundColor: AppTheme.primaryColor.withOpacity(0.15),
                backgroundImage:
                    _imageUrl != null ? NetworkImage(_imageUrl!) : null,
                child: _imageUrl == null
                    ? Icon(Icons.person,
                        color: AppTheme.primaryColor, size: 30)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Owner Name',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            _titleCtrl.text.isNotEmpty ? _titleCtrl.text : 'Title',
            style: TextStyle(
                color: AppTheme.primaryColor, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            _bioCtrl.text.isNotEmpty ? _bioCtrl.text : 'Bio goes here...',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
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
