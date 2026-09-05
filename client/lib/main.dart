import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/app_state.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await StorageService.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(storage),
      child: const CrossDropApp(),
    ),
  );
}

class CrossDropApp extends StatelessWidget {
  const CrossDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrossDrop',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: Consumer<AppState>(
        builder: (context, state, child) {
          if (state.isAuthenticated) {
            return const MainNavigation();
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }
}
