import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../data/auth_repository.dart';

/// `unknown`: ainda verificando se há sessão guardada (tela de carregamento).
enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.usuario,
    this.errorMessage,
    this.isLoading = false,
  });

  final AuthStatus status;
  final Map<String, dynamic>? usuario;
  final String? errorMessage;
  final bool isLoading;

  AuthState copyWith({
    AuthStatus? status,
    Map<String, dynamic>? usuario,
    String? errorMessage,
    bool clearError = false,
    bool? isLoading,
  }) =>
      AuthState(
        status: status ?? this.status,
        usuario: usuario ?? this.usuario,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repo)
      : super(const AuthState(status: AuthStatus.unknown)) {
    ApiClient.onSessaoExpirada = _aoSessaoExpirada;
  }

  final AuthRepository _repo;

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
      if (!mounted) return;
      state = AuthState(status: AuthStatus.authenticated, usuario: usuario);
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        await _repo.encerrarLocal();
        if (mounted) state = const AuthState(status: AuthStatus.unauthenticated);
      } else {
        state = const AuthState(status: AuthStatus.authenticated);
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
      state = state.copyWith(
        status: AuthStatus.authenticated,
        usuario: data['usuario'] as Map<String, dynamic>?,
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
      state = state.copyWith(
        status: AuthStatus.authenticated,
        usuario: data['usuario'] as Map<String, dynamic>?,
        isLoading: false,
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

  Future<void> toggleBiometria({required bool ativa}) async {
    try {
      final data = await _repo.setBiometria(ativa: ativa);
      state = state.copyWith(usuario: data);
    } catch (_) {}
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
  (ref) => AuthNotifier(ref.watch(authRepositoryProvider))..restaurarSessao(),
);
