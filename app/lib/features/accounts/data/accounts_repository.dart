import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/storage/local_database.dart';

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => AccountsRepository(ref.watch(apiClientProvider)),
);

class AccountsRepository {
  AccountsRepository(this._client);
  final ApiClient _client;

  Future<String> gerarConnectToken() async {
    final res = await _client.dio.post('/consentimentos/connect-token');
    return res.data['connectToken'] as String;
  }

  Future<Map<String, dynamic>> registrarConsentimento(String itemId) async {
    final res = await _client.dio.post('/consentimentos', data: {'itemId': itemId});
    return res.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> listarConsentimentos() async {
    final res = await _client.dio.get('/consentimentos');
    return res.data as List<dynamic>;
  }

  Future<void> revogarConsentimento(int id) async {
    await _client.dio.delete('/consentimentos/$id');
  }

  Future<Map<String, dynamic>> saldoConsolidado() async {
    final res = await _client.dio.get('/contas/saldo');
    final saldo = res.data as Map<String, dynamic>;
    try {
      await LocalDatabase.salvarSaldo(saldo);
    } catch (_) {} // falha no cache não pode esconder o saldo recebido
    return saldo;
  }

  /// Último saldo recebido, para mostrar na hora e sem internet (RNF09).
  Future<Map<String, dynamic>?> saldoDoCache() async {
    try {
      return await LocalDatabase.buscarSaldo();
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> listarContas() async {
    final res = await _client.dio.get('/contas');
    return res.data as List<dynamic>;
  }
}
