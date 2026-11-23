import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/push/push_service.dart';
import '../../../accounts/presentation/providers/accounts_provider.dart';
import '../../../auth/presentation/screens/profile_screen.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../home/presentation/screens/home_screen.dart';
import '../../../notifications/presentation/providers/notificacoes_provider.dart';
import '../../../notifications/presentation/screens/notificacoes_screen.dart';
import '../../../transactions/presentation/providers/transacoes_provider.dart';
import '../../../transactions/presentation/screens/transacoes_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    TransacoesScreen(),
    DashboardScreen(),
    NotificacoesScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(notificacoesProvider.notifier).carregarContagem();
      // Push (opt-in; ver FCM_ENABLED): registra o token e avisa quando chega um alerta.
      ref.read(pushServiceProvider).iniciar(aoReceber: (titulo, corpo) {
        if (!mounted) return;
        ref.read(notificacoesProvider.notifier).carregarContagem();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text([titulo, corpo].whereType<String>().join(': '))),
        );
      });
    });
  }

  @override
  void dispose() {
    ref.read(pushServiceProvider).parar();
    super.dispose();
  }

  /// O IndexedStack monta as abas uma única vez, na abertura; sem isto, dados
  /// sincronizados depois (transações, alertas) só apareciam ao atualizar na mão.
  /// Ao entrar numa aba, recarrega os dados dela.
  void _aoSelecionar(int i) {
    setState(() => _index = i);
    switch (i) {
      case 0:
        ref.invalidate(saldoProvider);
      case 1:
        ref.read(transacoesProvider.notifier).carregar();
      case 2:
        ref.invalidate(categoriasDashboardProvider);
        ref.invalidate(resumoMensalProvider);
      case 3:
        ref.read(notificacoesProvider.notifier).carregar();
        ref.read(notificacoesProvider.notifier).carregarContagem();
    }
  }

  @override
  Widget build(BuildContext context) {
    final naoLidas = ref.watch(
      notificacoesProvider.select((s) => s.naoLidas),
    );

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _aoSelecionar,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Início',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transações',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Relatórios',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: naoLidas > 0,
              label: Text(naoLidas > 9 ? '9+' : '$naoLidas'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: naoLidas > 0,
              label: Text(naoLidas > 9 ? '9+' : '$naoLidas'),
              child: const Icon(Icons.notifications),
            ),
            label: 'Alertas',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
