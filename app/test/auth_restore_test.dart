import 'package:dio/dio.dart';
import 'package:finance_control/core/api/api_client.dart';
import 'package:finance_control/features/auth/data/auth_repository.dart';
import 'package:finance_control/features/auth/presentation/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({
    this.tokens = true,
    this.meResult,
    this.meError,
  }) : super(ApiClient());

  final bool tokens;
  final Map<String, dynamic>? meResult;
  final DioException? meError;
  int meCalls = 0;
  int encerrarCalls = 0;

  @override
  Future<bool> temSessao() async => tokens;

  @override
  Future<Map<String, dynamic>> me() async {
    meCalls++;
    if (meError != null) throw meError!;
    return meResult ?? {};
  }

  @override
  Future<void> encerrarLocal() async => encerrarCalls++;
}

DioException _erro({int? status}) {
  final req = RequestOptions(path: '/auth/me');
  return DioException(
    requestOptions: req,
    response: status == null ? null : Response(requestOptions: req, statusCode: status),
    type: status == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
  );
}

void main() {
  tearDown(() => ApiClient.onSessaoExpirada = null);

  test('começa em "unknown" até a verificação terminar', () {
    final n = AuthNotifier(_FakeAuthRepository());
    expect(n.state.status, AuthStatus.unknown);
    n.dispose();
  });

  test('sem tokens guardados vai para o login e nem consulta o servidor', () async {
    final repo = _FakeAuthRepository(tokens: false);
    final n = AuthNotifier(repo);
    await n.restaurarSessao();

    expect(n.state.status, AuthStatus.unauthenticated);
    expect(repo.meCalls, 0);
    n.dispose();
  });

  test('sessão válida: autenticado e com os dados do usuário', () async {
    final repo = _FakeAuthRepository(meResult: {'nome': 'Julia', 'email': 'j@x.com'});
    final n = AuthNotifier(repo);
    await n.restaurarSessao();

    expect(n.state.status, AuthStatus.authenticated);
    expect(n.state.usuario?['nome'], 'Julia');
    n.dispose();
  });

  test('servidor recusa (401): limpa a sessão local e volta ao login', () async {
    final repo = _FakeAuthRepository(meError: _erro(status: 401));
    final n = AuthNotifier(repo);
    await n.restaurarSessao();

    expect(n.state.status, AuthStatus.unauthenticated);
    expect(repo.encerrarCalls, 1);
    n.dispose();
  });

  test('sem conexão: mantém a sessão para abrir offline', () async {
    final repo = _FakeAuthRepository(meError: _erro());
    final n = AuthNotifier(repo);
    await n.restaurarSessao();

    expect(n.state.status, AuthStatus.authenticated);
    expect(repo.encerrarCalls, 0);
    n.dispose();
  });

  test('erro 500 do servidor não derruba a sessão', () async {
    final repo = _FakeAuthRepository(meError: _erro(status: 500));
    final n = AuthNotifier(repo);
    await n.restaurarSessao();

    expect(n.state.status, AuthStatus.authenticated);
    n.dispose();
  });

  test('refresh recusado durante o uso desloga com aviso', () async {
    final repo = _FakeAuthRepository(meResult: {'nome': 'Julia'});
    final n = AuthNotifier(repo);
    await n.restaurarSessao();
    expect(n.state.status, AuthStatus.authenticated);

    ApiClient.onSessaoExpirada!();
    await Future<void>.delayed(Duration.zero);

    expect(n.state.status, AuthStatus.unauthenticated);
    expect(n.state.errorMessage, contains('Sessão expirada'));
    expect(repo.encerrarCalls, 1);
    n.dispose();
  });
}
