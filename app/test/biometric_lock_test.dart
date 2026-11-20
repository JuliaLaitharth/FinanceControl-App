import 'package:finance_control/features/auth/data/auth_repository.dart';
import 'package:finance_control/features/auth/data/biometric_service.dart';
import 'package:finance_control/features/auth/presentation/providers/auth_provider.dart';
import 'package:finance_control/features/auth/presentation/screens/biometric_lock_screen.dart';
import 'package:finance_control/features/auth/presentation/widgets/biometric_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Sobe o app com o Gate + tela de bloqueio e a sessão já restaurada e bloqueada.
Future<({FakeAuthRepository repo, FakeBiometricService bio, ProviderContainer c})>
    _abrir(
  WidgetTester tester, {
  required FakeBiometricService bio,
  DateTime Function()? agora,
}) async {
  final repo = FakeAuthRepository(meResult: {'biometriaAtiva': true});
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(repo),
    biometricServiceProvider.overrideWithValue(bio),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) =>
            BiometricGate(agora: agora ?? DateTime.now, child: child!),
        home: const Scaffold(body: Text('CONTEUDO')),
      ),
    ),
  );
  // O authProvider restaura a sessão sozinho ao ser lido (feito pelo Gate).
  await tester.pumpAndSettle();
  return (repo: repo, bio: bio, c: container);
}

void main() {
  testWidgets('biometria ok: desbloqueia e mostra o conteúdo', (tester) async {
    final r = await _abrir(tester, bio: FakeBiometricService(resultados: [true]));

    expect(r.c.read(authProvider).bloqueado, isFalse);
    expect(find.byType(BiometricLockScreen), findsNothing);
    expect(find.text('CONTEUDO'), findsOneWidget);
  });

  testWidgets('falha na biometria: continua bloqueado e mostra tentativas', (tester) async {
    await _abrir(tester, bio: FakeBiometricService(resultados: [false]));

    expect(find.byType(BiometricLockScreen), findsOneWidget);
    expect(find.text('CONTEUDO'), findsNothing);
    expect(find.textContaining('Tentativas restantes: 2'), findsOneWidget);
    expect(find.text('Usar biometria'), findsOneWidget);
  });

  testWidgets('após 3 falhas exige a senha e esconde a biometria', (tester) async {
    final bio = FakeBiometricService();
    await _abrir(tester, bio: bio);
    expect(bio.autenticacoes, 1);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Usar biometria'));
      await tester.pumpAndSettle();
    }

    expect(bio.autenticacoes, kMaxFalhasBiometria);
    expect(find.text('Usar biometria'), findsNothing);
    expect(find.textContaining('Muitas tentativas'), findsOneWidget);
    expect(find.text('Entrar com senha'), findsOneWidget);
  });

  testWidgets('"Entrar com senha" encerra a sessão', (tester) async {
    final r = await _abrir(tester, bio: FakeBiometricService());

    await tester.tap(find.text('Entrar com senha'));
    await tester.pumpAndSettle();

    expect(r.repo.logoutCalls, 1);
    expect(r.c.read(authProvider).status, AuthStatus.unauthenticated);
    expect(find.byType(BiometricLockScreen), findsNothing);
  });

  testWidgets('aparelho sem biometria: só oferece a senha', (tester) async {
    final r = await _abrir(
      tester,
      bio: FakeBiometricService(estaDisponivel: false),
    );

    expect(find.textContaining('não está disponível'), findsOneWidget);
    expect(find.text('Usar biometria'), findsNothing);
    expect(find.text('Entrar com senha'), findsOneWidget);
    expect(r.bio.autenticacoes, 0);
  });

  group('volta do segundo plano', () {
    Future<void> trocarCiclo(WidgetTester tester, AppLifecycleState s) async {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pumpAndSettle();
    }

    testWidgets('depois de 30s ou mais, volta a bloquear', (tester) async {
      var agora = DateTime(2026, 11, 20, 10);
      final r = await _abrir(
        tester,
        bio: FakeBiometricService(resultados: [true]),
        agora: () => agora,
      );
      expect(r.c.read(authProvider).bloqueado, isFalse);

      await trocarCiclo(tester, AppLifecycleState.inactive);
      await trocarCiclo(tester, AppLifecycleState.hidden);
      await trocarCiclo(tester, AppLifecycleState.paused);
      agora = agora.add(kTempoAteBloquear);
      await trocarCiclo(tester, AppLifecycleState.hidden);
      await trocarCiclo(tester, AppLifecycleState.inactive);
      await trocarCiclo(tester, AppLifecycleState.resumed);

      expect(r.c.read(authProvider).bloqueado, isTrue);
    });

    testWidgets('saída rápida (menos de 30s) não bloqueia', (tester) async {
      var agora = DateTime(2026, 11, 20, 10);
      final r = await _abrir(
        tester,
        bio: FakeBiometricService(resultados: [true]),
        agora: () => agora,
      );

      await trocarCiclo(tester, AppLifecycleState.inactive);
      await trocarCiclo(tester, AppLifecycleState.hidden);
      await trocarCiclo(tester, AppLifecycleState.paused);
      agora = agora.add(const Duration(seconds: 5));
      await trocarCiclo(tester, AppLifecycleState.hidden);
      await trocarCiclo(tester, AppLifecycleState.inactive);
      await trocarCiclo(tester, AppLifecycleState.resumed);

      expect(r.c.read(authProvider).bloqueado, isFalse);
    });
  });
}
