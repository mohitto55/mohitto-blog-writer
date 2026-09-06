import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/screens/workspace_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 블로그 mint 스킨의 primary(#11999e)를 앱 색상 기준으로 사용
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF11999E));
    return MaterialApp(
      title: 'Mohitto Blog Writer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: scheme.surface,
        visualDensity: VisualDensity.compact,
        tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
        inputDecorationTheme: const InputDecorationTheme(isDense: true),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, width: 480),
      ),
      home: const WorkspaceScreen(),
    );
  }
}
