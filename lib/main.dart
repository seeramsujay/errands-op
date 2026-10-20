import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/database/app_database.dart';
import 'state/app_state.dart';
import 'ui/screens/main_errand_screen.dart';
import 'ui/screens/map_view_screen.dart';
import 'ui/screens/stores_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite database with seed data
  await AppDatabase.instance.init();

  runApp(const OpListApp());
}

class OpListApp extends StatelessWidget {
  const OpListApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>(
      create: (_) => AppState(database: AppDatabase.instance)..initialize(),
      child: MaterialApp(
        title: 'op-list',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AppNavigationShell(),
      ),
    );
  }
}

class AppNavigationShell extends StatefulWidget {
  const AppNavigationShell({super.key});

  @override
  State<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends State<AppNavigationShell> {
  int _currentIndex = 0;

  final _screens = const [
    MainErrandScreen(),
    MapViewScreen(),
    StoresScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        backgroundColor: const Color(0xFF0F172A),
        indicatorColor: const Color(0xFF6366F1).withValues(alpha: 0.3),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist, color: Color(0xFF818CF8)),
            label: 'Errands',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: Color(0xFF818CF8)),
            label: 'Radar Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront, color: Color(0xFF818CF8)),
            label: 'Stores & DAG',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Color(0xFF818CF8)),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
