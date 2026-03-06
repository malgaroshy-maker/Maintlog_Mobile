import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/login_screen.dart';
import 'screens/logbook_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/checklist_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/ai_assistant_screen.dart';
import 'screens/settings_screen.dart';
import 'services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ldxcqnornpwifxuqisau.supabase.co',
    anonKey: 'sb_publishable_C9rgrC-QBP9Ayc8Vp8CZ1A_4kfMn5nU',
  );

  final prefs = await SharedPreferences.getInstance();
  final stayLoggedIn = prefs.getBool('stayLoggedIn') ?? false;
  final session = Supabase.instance.client.auth.currentSession;

  final initialRoute = (stayLoggedIn && session != null) ? '/home' : '/login';

  // Start listening for Supabase Realtime events
  if (session != null) {
    SyncService().listen();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaintLogApp(initialRoute: initialRoute),
    ),
  );
}

class MaintLogApp extends StatelessWidget {
  final String initialRoute;
  const MaintLogApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider>(context);

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      locale: localeProvider.locale,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      themeMode: themeProvider.themeMode,
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const MainNavigationScreen(),
      },
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const LogbookScreen(),
    const DashboardScreen(),
    const ChecklistScreen(),
    const ReportsScreen(),
    const AiAssistantScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.table_chart),
            label: AppLocalizations.of(context)!.logbook,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard),
            label: AppLocalizations.of(context)!.dashboard,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.check_box),
            label: AppLocalizations.of(context)!.checklist,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bar_chart),
            label: AppLocalizations.of(context)!.reports,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.auto_awesome),
            label: AppLocalizations.of(context)!.aiAssistant,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: AppLocalizations.of(context)!.settings,
          ),
        ],
      ),
    );
  }
}
