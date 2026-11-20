import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:3000', // Android emulator → localhost do host
);

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio _dio;

  static const _storage = FlutterSecureStorage();
  static const _keyAccessToken = 'access_token';
  static const _keyRefreshToken = 'refresh_token';

  /// Chamado quando o servidor recusa o refresh token (sessão expirada/revogada).
  static void Function()? onSessaoExpirada;

  /// O refresh token rotaciona no backend: requisições simultâneas com 401
  /// precisam compartilhar uma única renovação, senão a segunda falha.
  Future<bool>? _refreshEmAndamento;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _kBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ),
    );
  }

  Dio get dio => _dio;

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: _keyAccessToken);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final opts = err.requestOptions;
    final ehRotaAuth = opts.path.startsWith('/auth/login') ||
        opts.path.startsWith('/auth/register') ||
        opts.path.startsWith('/auth/refresh');
    final jaTentou = opts.extra['retried'] == true;

    if (err.response?.statusCode == 401 && !ehRotaAuth && !jaTentou) {
      final refreshed = await (_refreshEmAndamento ??=
          _tryRefresh().whenComplete(() => _refreshEmAndamento = null));
      if (refreshed) {
        final token = await _storage.read(key: _keyAccessToken);
        opts.extra['retried'] = true;
        opts.headers['Authorization'] = 'Bearer $token';
        try {
          final response = await _dio.fetch(opts);
          return handler.resolve(response);
        } catch (_) {}
      }
    }
    handler.next(err);
  }

  Future<bool> _tryRefresh() async {
    final refresh = await _storage.read(key: _keyRefreshToken);
    if (refresh == null) return false;
    try {
      final response = await Dio().post(
        '$_kBaseUrl/auth/refresh',
        data: {'refreshToken': refresh},
      );
      await saveTokens(
        accessToken: response.data['accessToken'] as String,
        refreshToken: response.data['refreshToken'] as String,
      );
      return true;
    } on DioException catch (e) {
      // Só encerra a sessão se o servidor recusou o token. Falha de rede
      // (sem conexão, timeout) mantém os tokens para tentar de novo depois.
      final status = e.response?.statusCode;
      if (status == 400 || status == 401 || status == 403) {
        await clearTokens();
        onSessaoExpirada?.call();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Há um refresh token guardado? (não valida com o servidor)
  static Future<bool> temSessao() async {
    try {
      final refresh = await _storage.read(key: _keyRefreshToken);
      return refresh != null && refresh.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
  }

  static Future<void> clearTokens() async {
    await _storage.deleteAll();
  }
}
