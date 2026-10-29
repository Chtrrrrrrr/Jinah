import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/settings_controller.dart';
import 'router.dart';
import 'theme.dart';

class JinahApp extends ConsumerWidget {
  const JinahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsControllerProvider);

    return MaterialApp.router(
      title: 'Jinah',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildJinahTheme(
        p: ObsidianPalette.light,
        accent: settings.accent,
        brightness: Brightness.light,
      ),
      darkTheme: buildJinahTheme(
        p: ObsidianPalette.dark,
        accent: settings.accent,
        brightness: Brightness.dark,
      ),
      themeMode: settings.themeMode,
    );
  }
}
