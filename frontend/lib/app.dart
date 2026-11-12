import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/projects/presentation/pages/projects_dashboard_page.dart';

class OpenDigitalTwinApp extends StatelessWidget {
  const OpenDigitalTwinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open Digital Twin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const ProjectsDashboardPage(),
    );
  }
}
