import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(apiClientProvider)),
);

class DashboardRepository {
  DashboardRepository(this._client);
  final ApiClient _client;

  /// Despesas por categoria no período [dataInicio, dataFim). Sem datas: mês atual.
  Future<List<Map<String, dynamic>>> resumoCategorias({
    String? dataInicio,
    String? dataFim,
  }) async {
    final res = await _client.dio.get(
      '/transacoes/resumo-categorias',
      queryParameters: {
        if (dataInicio != null) 'dataInicio': dataInicio,
        if (dataFim != null) 'dataFim': dataFim,
      },
    );
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['categorias'] as List);
  }

  Future<List<Map<String, dynamic>>> resumoMensal({int meses = 6, String? referencia}) async {
    final res = await _client.dio.get(
      '/transacoes/resumo-mensal',
      queryParameters: {'meses': meses, if (referencia != null) 'referencia': referencia},
    );
    final data = res.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['meses'] as List);
  }
}
