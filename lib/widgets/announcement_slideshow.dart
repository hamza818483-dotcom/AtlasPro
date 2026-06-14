import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class AnnouncementSlideshow extends StatefulWidget {
  const AnnouncementSlideshow({super.key});
  @override
  State<AnnouncementSlideshow> createState() => _AnnouncementSlideshowState();
}

class _AnnouncementSlideshowState extends State<AnnouncementSlideshow> {
  List<Map<String, dynamic>> _cards = [];
  int _currentIndex = 0;
  Timer? _autoTimer;
  late PageController _pageCtrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _loadCards();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConstants.workerBaseUrl}/api/public/announcements'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final cards = List<Map<String, dynamic>>.from(
            (data['announcements'] ?? [])
                .where((c) => c['active'] == true || c['active'] == 1));
        setState(() => _cards = cards);
        if (cards.length > 1) _startAutoSlide();
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _startAutoSlide() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _cards.isEmpty) return;
      final next = (_currentIndex + 1) % _cards.length;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  Color _parseColor(String? hex) {
    try {
      final h = (hex ?? '#6C63FF').replaceAll('#', '');
      return Color(0xFF000000 | int.parse(h, radix: 16));
    } catch (_) {
      return AppTheme.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 80);
    if (_cards.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 80,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _cards.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (ctx, i) => _buildCard(_cards[i]),
          ),
        ),
        if (_cards.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _cards.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: i == _currentIndex ? 20 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: i == _currentIndex
                      ? _parseColor(_cards[_currentIndex]['color'])
                      : Colors.white24,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> card) {
    final color = _parseColor(card['color']);
    final hasLink = (card['link'] ?? '').isNotEmpty;

    return GestureDetector(
      onTap: hasLink
          ? () async {
              final uri = Uri.tryParse(card['link']);
              if (uri != null) await launchUrl(uri);
            }
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.25), color.withOpacity(0.08)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35), width: 1.2),
        ),
        child: Row(
          children: [
            Text(card['emoji'] ?? '📢',
                style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card['title'] ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((card['body'] ?? '').isNotEmpty)
                    Text(
                      card['body'],
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (hasLink)
              Icon(Icons.arrow_forward_ios, color: color, size: 14),
          ],
        ),
      ),
    );
  }
}
