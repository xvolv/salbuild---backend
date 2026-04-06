import 'package:flutter/material.dart';

import 'screens/calendar_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/reframe_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tasks_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _screens = const [
    ReframeScreen(),
    TasksScreen(),
    NotesScreen(),
    CalendarScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tune), label: 'Reframe'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.note_alt), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Calendar'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
