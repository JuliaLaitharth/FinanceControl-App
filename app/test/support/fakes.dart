import 'package:dio/dio.dart';
import 'package:finance_control/core/api/api_client.dart';
import 'package:finance_control/features/auth/data/auth_repository.dart';
import 'package:finance_control/features/auth/data/biometric_service.dart';

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({
    this.tokens = true,
    this.meResult,
    this.meError,
  }) : super(ApiClient());

  final bool tokens;
  final Map<String, dynamic>? meResult;
  final DioException? meError;
  DioException? loginError;
  int meCalls = 0;
  int encerrarCalls = 0;
  int logoutCalls = 0;
  bool? ultimaBiometriaEnviada;

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

  @override
  Future<Map<String, dynamic>> login({required String email, required String senha}) async {
    if (loginError != null) throw loginError!;
    return {'usuario': {'email': email}};
  }

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  Future<Map<String, dynamic>> setBiometria({required bool ativa}) async {
    ultimaBiometriaEnviada = ativa;
    return {'biometriaAtiva': ativa};
  }
}

class FakeBiometricService implements BiometricService {
  FakeBiometricService({
    this.estaDisponivel = true,
    this.resultados = const [],
    bool ativaLocal = false,
  }) : _ativaLocal = ativaLocal;

  bool estaDisponivel;

  /// Respostas sucessivas de `autenticar`; acabando a lista, devolve `false`.
  final List<bool> resultados;
  int autenticacoes = 0;
  bool _ativaLocal;

  @override
  Future<bool> disponivel() async => estaDisponivel;

  @override
  Future<bool> autenticar(String motivo) async {
    final i = autenticacoes++;
    return i < resultados.length ? resultados[i] : false;
  }

  @override
  Future<bool> lerAtiva() async => _ativaLocal;

  @override
  Future<void> salvarAtiva(bool ativa) async => _ativaLocal = ativa;

  bool get ativaLocal => _ativaLocal;
}

DioException erroDio({int? status}) {
  final req = RequestOptions(path: '/auth/me');
  return DioException(
    requestOptions: req,
    response: status == null ? null : Response(requestOptions: req, statusCode: status),
    type: status == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
  );
}
