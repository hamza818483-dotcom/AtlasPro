import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'router.dart';
import 'core/theme.dart';
import 'services/access_service.dart';
import 'services/offline_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Sync page limits from server (non-blocking)
  AccessService.syncLimits().catchError((_) {});

  // Sync pending offline page views / exam results
  OfflineService.syncPending().catchError((_) {});

  runApp(const AtlasProApp());
}

class AtlasProApp extends StatelessWidget {
  const AtlasProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AtlasPro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
    );
  }
}
