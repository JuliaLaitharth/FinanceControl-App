import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

final regrasAlertaRepositoryProvider = Provider<RegrasAlertaRepository>(
  (ref) => RegrasAlertaRepository(ref.watch(apiClientProvider)),
);

class RegrasAlertaRepository {
  RegrasAlertaRepository(this._client);
  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listar() async {
    final res = await _client.dio.get('/regras-alerta');
    return List<Map<String, dynamic>>.from(res.data as List);
  }

  Future<void> criar(Map<String, dynamic> dados) async {
    await _client.dio.post('/regras-alerta', data: dados);
  }

  Future<void> atualizar(int id, Map<String, dynamic> dados) async {
    await _client.dio.patch('/regras-alerta/$id', data: dados);
  }

  Future<void> excluir(int id) async {
    await _client.dio.delete('/regras-alerta/$id');
  }
}
