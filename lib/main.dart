import 'package:flutter/material.dart';
import 'services/storage_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时读取保存的主题预设并应用（设置页里可随时切换）
  final presetIndex = await StorageService().loadThemePresetIndex();
  ThemeController.apply(ThemePreset.fromIndex(presetIndex));
  runApp(const UnraidMobileApp());
}

class UnraidMobileApp extends StatelessWidget {
  const UnraidMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemePreset>(
      valueListenable: ThemeController.current,
      builder: (context, preset, _) {
        final brightness = preset.brightness;
        return MaterialApp(
          title: 'Unraid Mobile',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: brightness == null
              ? ThemeMode.system
              : (brightness == Brightness.light
                  ? ThemeMode.light
                  : ThemeMode.dark),
          home: const _StartupGate(),
        );
      },
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
