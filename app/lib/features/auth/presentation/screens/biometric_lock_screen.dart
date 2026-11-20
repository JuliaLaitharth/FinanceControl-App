import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/biometric_service.dart';
import '../providers/auth_provider.dart';

/// Número de falhas seguidas até exigir a senha (RF01).
const kMaxFalhasBiometria = 3;

/// Tela de bloqueio: pede a biometria e, após [kMaxFalhasBiometria] falhas
/// (ou se o aparelho não tiver biometria), oferece entrar com a senha.
///
/// "Entrar com senha" encerra a sessão local: o usuário volta ao login.
class BiometricLockScreen extends ConsumerStatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  ConsumerState<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends ConsumerState<BiometricLockScreen> {
  int _falhas = 0;
  bool _autenticando = false;
  bool _indisponivel = false;

  bool get _exigirSenha => _indisponivel || _falhas >= kMaxFalhasBiometria;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tentar());
  }

  Future<void> _tentar() async {
    if (_autenticando || _exigirSenha || !mounted) return;
    final bio = ref.read(biometricServiceProvider);

    setState(() => _autenticando = true);
    if (!await bio.disponivel()) {
      if (mounted) {
        setState(() {
          _autenticando = false;
          _indisponivel = true;
        });
      }
      return;
    }

    final ok = await bio.autenticar('Desbloqueie o FinanceControl');
    if (!mounted) return;
    if (ok) {
      ref.read(authProvider.notifier).desbloquear();
      return;
    }
    setState(() {
      _autenticando = false;
      _falhas++;
    });
  }

  Future<void> _entrarComSenha() => ref.read(authProvider.notifier).logout();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final restantes = kMaxFalhasBiometria - _falhas;

    final String mensagem;
    if (_indisponivel) {
      mensagem = 'A biometria não está disponível neste aparelho. Entre com sua senha.';
    } else if (_falhas >= kMaxFalhasBiometria) {
      mensagem = 'Muitas tentativas sem sucesso. Entre com sua senha.';
    } else if (_falhas > 0) {
      mensagem = 'Biometria não reconhecida. Tentativas restantes: $restantes.';
    } else {
      mensagem = 'Use sua biometria para continuar.';
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: cs.primary),
                const SizedBox(height: 16),
                Text('FinanceControl bloqueado', style: tt.titleLarge),
                const SizedBox(height: 8),
                Text(
                  mensagem,
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(
                    color: _falhas > 0 ? cs.error : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                if (!_exigirSenha)
                  FilledButton.icon(
                    onPressed: _autenticando ? null : _tentar,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Usar biometria'),
                  ),
                const SizedBox(height: 12),
                _exigirSenha
                    ? FilledButton(
                        onPressed: _entrarComSenha,
                        child: const Text('Entrar com senha'),
                      )
                    : TextButton(
                        onPressed: _entrarComSenha,
                        child: const Text('Entrar com senha'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
