import 'package:flutter/material.dart';

import 'home_shell.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7C4DFF),
        brightness: Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'Reframe',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const HomeShell(),
    );
  }
}
