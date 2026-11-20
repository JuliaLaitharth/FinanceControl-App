import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/widgets/biometric_gate.dart';
import 'features/main/presentation/screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // As telas formatam datas com DateFormat(..., 'pt_BR'); sem isto o intl lança
  // LocaleDataException.
  await initializeDateFormatting('pt_BR');
  Intl.defaultLocale = 'pt_BR';
  runApp(const ProviderScope(child: FinanceControlApp()));
}

class FinanceControlApp extends ConsumerWidget {
  const FinanceControlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    final Widget home = switch (authState.status) {
      AuthStatus.unknown => const _SplashScreen(),
      AuthStatus.authenticated => const MainShell(),
      AuthStatus.unauthenticated => const LoginScreen(),
    };

    return MaterialApp(
      title: 'FinanceControl',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // O bloqueio por biometria fica fora do Navigator para cobrir todas as telas.
      builder: (context, child) => BiometricGate(child: child ?? const SizedBox.shrink()),
      home: home,
    );
  }
}

/// Exibida enquanto o app verifica se existe uma sessão guardada.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
