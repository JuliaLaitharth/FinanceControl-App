import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../data/auth_repository.dart';
import '../../data/biometric_service.dart';

/// `unknown`: ainda verificando se há sessão guardada (tela de carregamento).
enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.usuario,
    this.errorMessage,
    this.isLoading = false,
    this.bloqueado = false,
  });

  final AuthStatus status;
  final Map<String, dynamic>? usuario;
  final String? errorMessage;
  final bool isLoading;

  /// Sessão válida, mas o app está travado aguardando a biometria.
  final bool bloqueado;

  AuthState copyWith({
    AuthStatus? status,
    Map<String, dynamic>? usuario,
    String? errorMessage,
    bool clearError = false,
    bool? isLoading,
    bool? bloqueado,
  }) =>
      AuthState(
        status: status ?? this.status,
        usuario: usuario ?? this.usuario,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        isLoading: isLoading ?? this.isLoading,
        bloqueado: bloqueado ?? this.bloqueado,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repo, this._bio)
      : super(const AuthState(status: AuthStatus.unknown)) {
    ApiClient.onSessaoExpirada = _aoSessaoExpirada;
  }

  final AuthRepository _repo;
  final BiometricService _bio;

  /// A biometria está ativa? Usa o dado do servidor quando há; offline, a
  /// preferência guardada no aparelho. Também mantém essa cópia local em dia.
  Future<bool> _biometriaAtiva(Map<String, dynamic>? usuario) async {
    final doServidor = usuario?['biometriaAtiva'];
    if (doServidor is bool) {
      await _bio.salvarAtiva(doServidor);
      return doServidor;
    }
    return _bio.lerAtiva();
  }

  /// Trava o app (ex.: ao voltar do segundo plano) se a biometria estiver ativa.
  Future<void> bloquearSeAtiva() async {
    if (state.status != AuthStatus.authenticated || state.bloqueado) return;
    if (await _biometriaAtiva(state.usuario) && mounted) {
      state = state.copyWith(bloqueado: true);
    }
  }

  void desbloquear() => state = state.copyWith(bloqueado: false);

  @override
  void dispose() {
    ApiClient.onSessaoExpirada = null;
    super.dispose();
  }

  /// Chamado na abertura do app: retoma a sessão guardada, se houver.
  ///
  /// - Sem tokens → login.
  /// - Servidor aceita (renovando o token, se preciso) → autenticado.
  /// - Servidor recusa (401/403) → limpa tudo e volta ao login.
  /// - Sem conexão ou erro 5xx → mantém a sessão, para o app abrir offline
  ///   com os dados em cache; um 401 posterior cai em [_aoSessaoExpirada].
  Future<void> restaurarSessao() async {
    if (!await _repo.temSessao()) {
      if (mounted) state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final usuario = await _repo.me();
      final bloqueado = await _biometriaAtiva(usuario);
      if (!mounted) return;
      state = AuthState(
        status: AuthStatus.authenticated,
        usuario: usuario,
        bloqueado: bloqueado,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        await _repo.encerrarLocal();
        if (mounted) state = const AuthState(status: AuthStatus.unauthenticated);
      } else {
        // Offline: usa a preferência guardada no aparelho.
        final bloqueado = await _biometriaAtiva(null);
        if (mounted) {
          state = AuthState(status: AuthStatus.authenticated, bloqueado: bloqueado);
        }
      }
    } catch (_) {
      if (mounted) state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> _aoSessaoExpirada() async {
    await _repo.encerrarLocal();
    if (!mounted) return;
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      errorMessage: 'Sessão expirada. Faça login novamente.',
    );
  }

  Future<void> register({
    required String nome,
    required String email,
    required String senha,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _repo.register(nome: nome, email: email, senha: senha);
      final usuario = data['usuario'] as Map<String, dynamic>?;
      await _biometriaAtiva(usuario); // guarda a preferência; sem bloqueio após digitar a senha
      state = state.copyWith(
        status: AuthStatus.authenticated,
        usuario: usuario,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: _parseError(e),
        isLoading: false,
      );
    }
  }

  Future<void> login({required String email, required String senha}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _repo.login(email: email, senha: senha);
      final usuario = data['usuario'] as Map<String, dynamic>?;
      await _biometriaAtiva(usuario); // guarda a preferência; sem bloqueio após digitar a senha
      state = state.copyWith(
        status: AuthStatus.authenticated,
        usuario: usuario,
        isLoading: false,
        bloqueado: false,
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: _parseError(e),
        isLoading: false,
      );
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> forgotPassword(String email) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.forgotPassword(email);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(errorMessage: _parseError(e), isLoading: false);
    }
  }

  /// Redefine a senha com o código recebido por e-mail. Retorna a mensagem de erro, ou `null`.
  Future<String?> redefinirSenha({required String codigo, required String novaSenha}) async {
    try {
      await _repo.resetPassword(token: codigo, novaSenha: novaSenha);
      return null;
    } catch (e) {
      return _parseError(e);
    }
  }

  /// Ativa/desativa a biometria. Retorna a mensagem de erro, ou `null` se deu certo.
  ///
  /// Para ativar, o aparelho precisa ter biometria e o usuário precisa
  /// confirmá-la agora; assim ninguém fica trancado fora do app por engano.
  Future<String?> toggleBiometria({required bool ativa}) async {
    if (ativa) {
      if (!await _bio.disponivel()) {
        return 'Biometria indisponível. Cadastre uma digital ou o Face ID nos ajustes do aparelho.';
      }
      if (!await _bio.autenticar('Confirme sua identidade para ativar a biometria')) {
        return 'Não foi possível confirmar a biometria.';
      }
    }
    try {
      final data = await _repo.setBiometria(ativa: ativa);
      await _bio.salvarAtiva(ativa);
      if (mounted) state = state.copyWith(usuario: data);
      return null;
    } catch (e) {
      return _parseError(e);
    }
  }

  Future<bool> atualizarNome(String nome) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _repo.atualizarPerfil(nome: nome);
      state = state.copyWith(usuario: data, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _parseError(e), isLoading: false);
      return false;
    }
  }

  Future<bool> alterarEmail({
    required String senhaAtual,
    required String novoEmail,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _repo.alterarEmail(senhaAtual: senhaAtual, novoEmail: novoEmail);
      state = state.copyWith(usuario: data, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _parseError(e), isLoading: false);
      return false;
    }
  }

  Future<bool> alterarSenha({
    required String senhaAtual,
    required String novaSenha,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.alterarSenha(senhaAtual: senhaAtual, novaSenha: novaSenha);
      state = state.copyWith(isLoading: false);
      await logout();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _parseError(e), isLoading: false);
      return false;
    }
  }

  Future<bool> excluirConta() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repo.excluirConta();
      state = const AuthState(status: AuthStatus.unauthenticated);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: _parseError(e), isLoading: false);
      return false;
    }
  }

  String _parseError(Object e) {
    // Sem resposta do servidor (sem internet, endereço errado, servidor fora do ar):
    // dizer isso evita confundir com "e-mail ou senha incorretos".
    if (e is DioException && e.response == null) {
      return 'Não foi possível conectar ao servidor. Verifique sua conexão e tente novamente.';
    }
    // Extrai mensagem de erro da API (DioException → response.data.message)
    try {
      final dynamic data = (e as dynamic).response?.data; // ignore: avoid_dynamic_calls
      if (data is Map) {
        final msg = data['message'];
        if (msg is String) return msg;
        if (msg is List<dynamic>) return msg.join(', ');
      }
    } catch (_) {}
    return 'Ocorreu um erro. Tente novamente.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(biometricServiceProvider),
  )..restaurarSessao(),
);
