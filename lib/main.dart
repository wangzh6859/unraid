import 'package:flutter/material.dart';
import 'services/storage_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const UnraidMobileApp());
}

class UnraidMobileApp extends StatelessWidget {
  const UnraidMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unraid Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const _StartupGate(),
    );
  }
}

/// 启动时判断是否已保存过连接信息，决定进入登录页还是主页。
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool? _hasConnection;

  @override
  void initState() {
    super.initState();
    StorageService().loadConnection().then((saved) {
      if (mounted) setState(() => _hasConnection = saved != null);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasConnection == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _hasConnection! ? const HomeScreen() : const LoginScreen();
  }
}
