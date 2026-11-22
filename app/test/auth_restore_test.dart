import 'package:finance_control/core/api/api_client.dart';
import 'package:finance_control/features/auth/presentation/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

AuthNotifier _notifier(FakeAuthRepository repo, [FakeBiometricService? bio]) =>
    AuthNotifier(repo, bio ?? FakeBiometricService());

void main() {
  tearDown(() => ApiClient.onSessaoExpirada = null);

  group('restauração de sessão', () {
    test('começa em "unknown" até a verificação terminar', () {
      final n = _notifier(FakeAuthRepository());
      expect(n.state.status, AuthStatus.unknown);
      n.dispose();
    });

    test('sem tokens guardados vai para o login e nem consulta o servidor', () async {
      final repo = FakeAuthRepository(tokens: false);
      final n = _notifier(repo);
      await n.restaurarSessao();

      expect(n.state.status, AuthStatus.unauthenticated);
      expect(repo.meCalls, 0);
      n.dispose();
    });

    test('sessão válida: autenticado e com os dados do usuário', () async {
      final repo = FakeAuthRepository(meResult: {'nome': 'Julia', 'email': 'j@x.com'});
      final n = _notifier(repo);
      await n.restaurarSessao();

      expect(n.state.status, AuthStatus.authenticated);
      expect(n.state.usuario?['nome'], 'Julia');
      expect(n.state.bloqueado, isFalse);
      n.dispose();
    });

    test('servidor recusa (401): limpa a sessão local e volta ao login', () async {
      final repo = FakeAuthRepository(meError: erroDio(status: 401));
      final n = _notifier(repo);
      await n.restaurarSessao();

      expect(n.state.status, AuthStatus.unauthenticated);
      expect(repo.encerrarCalls, 1);
      n.dispose();
    });

    test('sem conexão: mantém a sessão para abrir offline', () async {
      final repo = FakeAuthRepository(meError: erroDio());
      final n = _notifier(repo);
      await n.restaurarSessao();

      expect(n.state.status, AuthStatus.authenticated);
      expect(repo.encerrarCalls, 0);
      n.dispose();
    });

    test('erro 500 do servidor não derruba a sessão', () async {
      final repo = FakeAuthRepository(meError: erroDio(status: 500));
      final n = _notifier(repo);
      await n.restaurarSessao();

      expect(n.state.status, AuthStatus.authenticated);
      n.dispose();
    });

    test('refresh recusado durante o uso desloga com aviso', () async {
      final repo = FakeAuthRepository(meResult: {'nome': 'Julia'});
      final n = _notifier(repo);
      await n.restaurarSessao();
      expect(n.state.status, AuthStatus.authenticated);

      ApiClient.onSessaoExpirada!();
      await Future<void>.delayed(Duration.zero);

      expect(n.state.status, AuthStatus.unauthenticated);
      expect(n.state.errorMessage, contains('Sessão expirada'));
      expect(repo.encerrarCalls, 1);
      n.dispose();
    });
  });

  group('mensagens de erro do login', () {
    test('sem resposta do servidor: avisa que não conseguiu conectar', () async {
      final repo = FakeAuthRepository()..loginError = erroDio();
      final n = _notifier(repo);

      await n.login(email: 'a@b.com', senha: 'x');

      expect(n.state.status, isNot(AuthStatus.authenticated));
      expect(n.state.errorMessage, contains('conectar ao servidor'));
      n.dispose();
    });

    test('servidor responde 401: não diz que a conexão falhou', () async {
      final repo = FakeAuthRepository()..loginError = erroDio(status: 401);
      final n = _notifier(repo);

      await n.login(email: 'a@b.com', senha: 'x');

      expect(n.state.errorMessage, isNot(contains('conectar ao servidor')));
      n.dispose();
    });
  });

  group('bloqueio por biometria', () {
    test('biometria ativa no servidor: abre bloqueado', () async {
      final bio = FakeBiometricService();
      final n = _notifier(FakeAuthRepository(meResult: {'biometriaAtiva': true}), bio);
      await n.restaurarSessao();

      expect(n.state.status, AuthStatus.authenticated);
      expect(n.state.bloqueado, isTrue);
      expect(bio.ativaLocal, isTrue, reason: 'guarda a preferência para uso offline');
      n.dispose();
    });

    test('biometria desativada: abre direto', () async {
      final n = _notifier(FakeAuthRepository(meResult: {'biometriaAtiva': false}));
      await n.restaurarSessao();

      expect(n.state.bloqueado, isFalse);
      n.dispose();
    });

    test('offline usa a preferência guardada no aparelho', () async {
      final bio = FakeBiometricService(ativaLocal: true);
      final n = _notifier(FakeAuthRepository(meError: erroDio()), bio);
      await n.restaurarSessao();

      expect(n.state.status, AuthStatus.authenticated);
      expect(n.state.bloqueado, isTrue);
      n.dispose();
    });

    test('desbloquear libera o app', () async {
      final n = _notifier(FakeAuthRepository(meResult: {'biometriaAtiva': true}));
      await n.restaurarSessao();
      n.desbloquear();

      expect(n.state.bloqueado, isFalse);
      n.dispose();
    });

    test('bloquearSeAtiva trava de novo só se a biometria estiver ativa', () async {
      final ativo = _notifier(FakeAuthRepository(meResult: {'biometriaAtiva': true}));
      await ativo.restaurarSessao();
      ativo.desbloquear();
      await ativo.bloquearSeAtiva();
      expect(ativo.state.bloqueado, isTrue);
      ativo.dispose();

      final inativo = _notifier(FakeAuthRepository(meResult: {'biometriaAtiva': false}));
      await inativo.restaurarSessao();
      await inativo.bloquearSeAtiva();
      expect(inativo.state.bloqueado, isFalse);
      inativo.dispose();
    });

    test('ativar exige aparelho com biometria', () async {
      final repo = FakeAuthRepository(meResult: {'biometriaAtiva': false});
      final n = _notifier(repo, FakeBiometricService(estaDisponivel: false));
      await n.restaurarSessao();

      final erro = await n.toggleBiometria(ativa: true);

      expect(erro, contains('indisponível'));
      expect(repo.ultimaBiometriaEnviada, isNull, reason: 'não chega ao servidor');
      n.dispose();
    });

    test('ativar exige confirmar a biometria agora', () async {
      final repo = FakeAuthRepository(meResult: {'biometriaAtiva': false});
      final n = _notifier(repo, FakeBiometricService(resultados: [false]));
      await n.restaurarSessao();

      final erro = await n.toggleBiometria(ativa: true);

      expect(erro, isNotNull);
      expect(repo.ultimaBiometriaEnviada, isNull);
      n.dispose();
    });

    test('ativar com sucesso grava no servidor e no aparelho', () async {
      final repo = FakeAuthRepository(meResult: {'biometriaAtiva': false});
      final bio = FakeBiometricService(resultados: [true]);
      final n = _notifier(repo, bio);
      await n.restaurarSessao();

      final erro = await n.toggleBiometria(ativa: true);

      expect(erro, isNull);
      expect(repo.ultimaBiometriaEnviada, isTrue);
      expect(bio.ativaLocal, isTrue);
      n.dispose();
    });

    test('desativar não pede biometria', () async {
      final repo = FakeAuthRepository(meResult: {'biometriaAtiva': true});
      final bio = FakeBiometricService();
      final n = _notifier(repo, bio);
      await n.restaurarSessao();

      final erro = await n.toggleBiometria(ativa: false);

      expect(erro, isNull);
      expect(bio.autenticacoes, 0);
      expect(repo.ultimaBiometriaEnviada, isFalse);
      n.dispose();
    });
  });
}
