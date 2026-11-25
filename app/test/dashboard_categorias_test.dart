import 'package:finance_control/core/api/api_client.dart';
import 'package:finance_control/features/dashboard/data/dashboard_repository.dart';
import 'package:finance_control/features/dashboard/presentation/periodo_relatorio.dart';
import 'package:finance_control/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:finance_control/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeDashboardRepo extends DashboardRepository {
  _FakeDashboardRepo() : super(ApiClient());

  String? ultimoInicio;
  String? ultimoFim;
  int chamadas = 0;
  int? ultimosMeses;
  String? ultimaReferencia;

  @override
  Future<List<Map<String, dynamic>>> resumoMensal({int meses = 6, String? referencia}) async {
    ultimosMeses = meses;
    ultimaReferencia = referencia;
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> resumoCategorias({
    String? dataInicio,
    String? dataFim,
  }) async {
    chamadas++;
    ultimoInicio = dataInicio;
    ultimoFim = dataFim;
    return [];
  }
}

final _categorias = [
  {'nome': 'Moradia', 'icone': '🏠', 'total': 800.0, 'quantidade': 1},
  {'nome': 'Outros', 'icone': '📦', 'total': 374.9, 'quantidade': 3},
  {'nome': 'Lazer', 'icone': '🎮', 'total': 77.8, 'quantidade': 2},
];

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('PeriodoRelatorio.intervalo', () {
    final hoje = DateTime(2026, 11, 20);

    test('mês atual: do dia 1º até hoje', () {
      final i = PeriodoRelatorio.mesAtual.intervalo(hoje);
      expect(i.inicio, '2026-11-01');
      expect(i.fim, isNull);
    });

    test('mês anterior: [1º do mês passado, 1º deste mês)', () {
      final i = PeriodoRelatorio.mesAnterior.intervalo(hoje);
      expect(i.inicio, '2026-10-01');
      expect(i.fim, '2026-11-01');
    });

    test('3 meses: começa no 1º dia de dois meses atrás', () {
      final i = PeriodoRelatorio.tresMeses.intervalo(hoje);
      expect(i.inicio, '2026-09-01');
      expect(i.fim, isNull);
    });

    test('virada de ano em janeiro', () {
      final jan = DateTime(2027, 1, 15);
      expect(PeriodoRelatorio.mesAnterior.intervalo(jan).inicio, '2026-12-01');
      expect(PeriodoRelatorio.mesAnterior.intervalo(jan).fim, '2027-01-01');
      expect(PeriodoRelatorio.tresMeses.intervalo(jan).inicio, '2026-11-01');
    });
  });

  group('gráfico mensal', () {
    test('o período escolhido muda a consulta mensal', () async {
      final repo = _FakeDashboardRepo();
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      await container.read(resumoMensalProvider.future);
      expect((repo.ultimosMeses, repo.ultimaReferencia), (6, null));

      container.read(periodoRelatorioProvider.notifier).state = PeriodoRelatorio.tresMeses;
      await container.read(resumoMensalProvider.future);
      expect((repo.ultimosMeses, repo.ultimaReferencia), (3, null));

      container.read(periodoRelatorioProvider.notifier).state = PeriodoRelatorio.mesAnterior;
      await container.read(resumoMensalProvider.future);
      expect(repo.ultimaReferencia, isNotNull);
    });

    test('"mês anterior" vira o ano em janeiro', () {
      final c = PeriodoRelatorio.mesAnterior.comparacaoMensal(DateTime(2027, 1, 15));
      expect((c.meses, c.referencia), (6, '2026-12'));
    });
  });

  group('categoriasDashboardProvider', () {
    test('envia o período escolhido ao backend', () async {
      final repo = _FakeDashboardRepo();
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      await container.read(categoriasDashboardProvider.future);
      expect(repo.ultimoFim, isNull, reason: 'mês atual não limita o fim');
      final inicioAtual = repo.ultimoInicio!;
      expect(inicioAtual, endsWith('-01'));

      container.read(periodoRelatorioProvider.notifier).state = PeriodoRelatorio.mesAnterior;
      await container.read(categoriasDashboardProvider.future);

      expect(repo.chamadas, 2, reason: 'trocar o período refaz a consulta');
      expect(repo.ultimoFim, isNotNull);
      expect(repo.ultimoInicio, isNot(inicioAtual));
    });
  });

  group('DashboardScreen', () {
    Future<ProviderContainer> abrir(WidgetTester tester) async {
      final container = ProviderContainer(overrides: [
        categoriasDashboardProvider.overrideWith((ref) async => _categorias),
        resumoMensalProvider.overrideWith((ref) async => []),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('lista cada categoria com valor, percentual e lançamentos', (tester) async {
      await abrir(tester);

      expect(find.text('Por categoria'), findsOneWidget);
      // R$ 800,00 + 374,90 + 77,80 = 1.252,70
      expect(find.textContaining('1.252,70'), findsOneWidget);

      expect(find.text('🏠 Moradia'), findsOneWidget);
      expect(find.textContaining('63.9% · 1 lançamento'), findsOneWidget);
      expect(find.textContaining('29.9% · 3 lançamentos'), findsOneWidget);
      expect(find.textContaining('6.2% · 2 lançamentos'), findsOneWidget);
    });

    testWidgets('mostra os três períodos e troca ao tocar', (tester) async {
      final container = await abrir(tester);

      for (final p in PeriodoRelatorio.values) {
        expect(find.text(p.rotulo), findsOneWidget);
      }
      expect(container.read(periodoRelatorioProvider), PeriodoRelatorio.mesAtual);

      await tester.tap(find.text('3 meses'));
      await tester.pumpAndSettle();

      expect(container.read(periodoRelatorioProvider), PeriodoRelatorio.tresMeses);
    });

    testWidgets('sem despesas informa o período escolhido', (tester) async {
      final container = ProviderContainer(overrides: [
        categoriasDashboardProvider.overrideWith((ref) async => []),
        resumoMensalProvider.overrideWith((ref) async => []),
      ]);
      addTearDown(container.dispose);
      container.read(periodoRelatorioProvider.notifier).state = PeriodoRelatorio.mesAnterior;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma despesa no mês anterior'), findsOneWidget);
    });
  });
}
