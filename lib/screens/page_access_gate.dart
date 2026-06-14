// page_access_gate.dart
// pdf_viewer_screen.dart এ এই widget ব্যবহার করো page দেখানোর আগে

import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/access_service.dart';

/// PDF viewer এ প্রতি page change এ এটা call করো
/// Returns true = দেখতে পারবে, false = blocked
Future<bool> checkAndRecordPageAccess(
  BuildContext context,
  int pdfId,
  int pageNumber,
) async {
  final error = await AccessService.checkPageAccess();
  if (error != null) {
    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E1E2E),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🔒', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 20),
              FutureBuilder<int>(
                future: _getResetMinutes(),
                builder: (ctx, snap) => Text(
                  'রিসেট হবে: আজ রাত ১২টায় (${snap.data ?? '?'} মিনিট পরে)',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      child: const Text('বন্ধ করো'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/packages');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                      ),
                      child: const Text(
                        'প্রিমিয়াম নাও',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return false;
  }
  // Record view
  await AccessService.recordPageView(pdfId, pageNumber);
  return true;
}

Future<int> _getResetMinutes() async {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day + 1);
  return midnight.difference(now).inMinutes;
}

// ─── Page Remaining Badge Widget ─────────────────────────
/// PDF viewer header এ show করো
class PageRemainingBadge extends StatefulWidget {
  const PageRemainingBadge({super.key});
  @override
  State<PageRemainingBadge> createState() => _PageRemainingBadgeState();
}

class _PageRemainingBadgeState extends State<PageRemainingBadge> {
  int _remaining = 0;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AccessService.getRemainingPages();
    final p = await AccessService.isPremium();
    if (mounted) setState(() { _remaining = r; _isPremium = p; });
  }

  @override
  Widget build(BuildContext context) {
    if (_isPremium) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('⭐ Premium',
            style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _remaining <= 1
            ? Colors.red.withOpacity(0.15)
            : Colors.blue.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$_remaining পৃষ্ঠা বাকি',
        style: TextStyle(
          color: _remaining <= 1 ? Colors.red : Colors.blue,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
