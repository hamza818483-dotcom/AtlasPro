import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants.dart';
import '../../core/theme.dart';

class OwnerFlipCard extends StatefulWidget {
  const OwnerFlipCard({super.key});
  @override
  State<OwnerFlipCard> createState() => _OwnerFlipCardState();
}

class _OwnerFlipCardState extends State<OwnerFlipCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  bool _isFront = true;
  Map<String, dynamic> _owner = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut));

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _loadOwner();
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOwner() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/public/owner'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _owner = data['owner'] ?? {});
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _flip() {
    if (_flipCtrl.isAnimating) return;
    if (_isFront) {
      _flipCtrl.forward();
    } else {
      _flipCtrl.reverse();
    }
    setState(() => _isFront = !_isFront);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 160);
    if (_owner.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, child) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(_glowAnim.value * 0.5),
              blurRadius: 25,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: AppTheme.accentColor.withOpacity(_glowAnim.value * 0.3),
              blurRadius: 40,
              spreadRadius: -5,
            ),
          ],
        ),
        child: child,
      ),
      child: GestureDetector(
        onTap: _flip,
        child: AnimatedBuilder(
          animation: _flipAnim,
          builder: (_, __) {
            final angle = _flipAnim.value * math.pi;
            final isShowingFront = angle <= math.pi / 2;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(angle),
              child: isShowingFront ? _buildFront() : _buildBack(angle),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFront() {
    final picUrl = _owner['image_url'] as String?;
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.2),
            AppTheme.accentColor.withOpacity(0.1),
            const Color(0xFF1A1A2E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.primaryColor.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          // Photo with glow
          AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor
                        .withOpacity(_glowAnim.value * 0.6),
                    blurRadius: 20,
                    spreadRadius: 3,
                  ),
                ],
              ),
              child: child,
            ),
            child: CircleAvatar(
              radius: 48,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.15),
              backgroundImage:
                  picUrl != null ? NetworkImage(picUrl) : null,
              child: picUrl == null
                  ? Icon(Icons.person,
                      color: AppTheme.primaryColor, size: 36)
                  : null,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _owner['name'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _owner['title'] ?? '',
                  style: TextStyle(
                      color: AppTheme.primaryColor, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  _owner['bio'] ?? '',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.touch_app,
                        color: AppTheme.primaryColor.withOpacity(0.6),
                        size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'বিস্তারিত দেখতে ট্যাপ করো',
                      style: TextStyle(
                          color: AppTheme.primaryColor.withOpacity(0.6),
                          fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildBack(double angle) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(math.pi),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.accentColor.withOpacity(0.2),
              AppTheme.primaryColor.withOpacity(0.1),
              const Color(0xFF1A1A2E),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppTheme.accentColor.withOpacity(0.4), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '👤 ${_owner['name'] ?? ''}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
              const SizedBox(height: 8),
              if ((_owner['email'] ?? '').isNotEmpty)
                _contactRow(Icons.email, _owner['email']),
              if ((_owner['phone'] ?? '').isNotEmpty)
                _contactRow(Icons.phone, _owner['phone']),
              if ((_owner['facebook'] ?? '').isNotEmpty)
                _contactRow(Icons.link, _owner['facebook']),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
