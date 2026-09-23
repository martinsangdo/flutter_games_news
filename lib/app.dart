import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'views/main_shell.dart';
import 'views/splash_screen.dart';

class GamesNewsApp extends StatelessWidget {
  const GamesNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Games News',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const SplashGate(child: MainShell()),
    );
  }
}
