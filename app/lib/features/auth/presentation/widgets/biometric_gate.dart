import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../screens/biometric_lock_screen.dart';

/// Tempo em segundo plano a partir do qual o app volta a pedir a biometria.
const kTempoAteBloquear = Duration(seconds: 30);

/// Envolve o Navigator do app (via `MaterialApp.builder`) para que o bloqueio
/// cubra também as telas empilhadas. Enquanto bloqueado, o conteúdo continua
/// montado (mantém a navegação), só fica fora da tela.
class BiometricGate extends ConsumerStatefulWidget {
  const BiometricGate({super.key, required this.child, this.agora = DateTime.now});

  final Widget child;

  /// Relógio injetável, para testar o tempo em segundo plano.
  final DateTime Function() agora;

  @override
  ConsumerState<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends ConsumerState<BiometricGate>
    with WidgetsBindingObserver {
  DateTime? _foiParaSegundoPlano;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _foiParaSegundoPlano ??= widget.agora();
      case AppLifecycleState.resumed:
        final saiu = _foiParaSegundoPlano;
        _foiParaSegundoPlano = null;
        if (saiu != null && widget.agora().difference(saiu) >= kTempoAteBloquear) {
          ref.read(authProvider.notifier).bloquearSeAtiva();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloqueado = ref.watch(
      authProvider.select(
        (s) => s.status == AuthStatus.authenticated && s.bloqueado,
      ),
    );

    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Offstage(offstage: bloqueado, child: widget.child),
        if (bloqueado) const Positioned.fill(child: BiometricLockScreen()),
      ],
    );
  }
}
