import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dashboard_repository.dart';
import '../periodo_relatorio.dart';

/// Período escolhido no relatório de despesas por categoria.
final periodoRelatorioProvider =
    StateProvider<PeriodoRelatorio>((ref) => PeriodoRelatorio.mesAtual);

final categoriasDashboardProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final periodo = ref.watch(periodoRelatorioProvider);
  final intervalo = periodo.intervalo(DateTime.now());
  return ref.watch(dashboardRepositoryProvider).resumoCategorias(
        dataInicio: intervalo.inicio,
        dataFim: intervalo.fim,
      );
});

final resumoMensalProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final comparacao = ref.watch(periodoRelatorioProvider).comparacaoMensal(DateTime.now());
  return ref.watch(dashboardRepositoryProvider).resumoMensal(
        meses: comparacao.meses,
        referencia: comparacao.referencia,
      );
});
