import 'package:dio/dio.dart';
import 'package:finance_control/core/api/api_client.dart';
import 'package:finance_control/features/alert_rules/data/regras_alerta_repository.dart';
import 'package:finance_control/features/alert_rules/presentation/providers/regras_alerta_provider.dart';
import 'package:finance_control/features/alert_rules/presentation/regra_alerta_modelo.dart';
import 'package:finance_control/features/alert_rules/presentation/screens/regra_alerta_form_screen.dart';
import 'package:finance_control/features/transactions/presentation/providers/transacoes_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeRepo extends RegrasAlertaRepository {
  _FakeRepo({List<Map<String, dynamic>>? regras})
      : regras = regras ?? [],
        super(ApiClient());

  List<Map<String, dynamic>> regras;
  bool falhar = false;
  final criadas = <Map<String, dynamic>>[];
  final atualizadas = <int, Map<String, dynamic>>{};
  final excluidas = <int>[];

  DioException _erro(String msg) {
    final req = RequestOptions(path: '/regras-alerta');
    return DioException(
      requestOptions: req,
      response: Response(requestOptions: req, statusCode: 400, data: {'message': msg}),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listar() async => regras;

  @override
  Future<void> criar(Map<String, dynamic> dados) async {
    if (falhar) throw _erro('Informe um valor limite maior que zero.');
    criadas.add(dados);
  }

  @override
  Future<void> atualizar(int id, Map<String, dynamic> dados) async {
    if (falhar) throw _erro('Erro no servidor');
    atualizadas[id] = dados;
  }

  @override
  Future<void> excluir(int id) async {
    if (falhar) throw _erro('Erro no servidor');
    excluidas.add(id);
  }
}

Map<String, dynamic> _regra(int id, {bool ativa = true}) => {
      'id': id,
      'tipoEvento': 'TRANSACAO_GRANDE',
      'valorLimite': '500',
      'canal': 'PUSH',
      'ativa': ativa,
      'categoriaId': null,
      'categoria': null,
    };

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('parseValorBr', () {
    test('aceita formatos brasileiros e simples', () {
      expect(parseValorBr('1.234,56'), 1234.56);
      expect(parseValorBr('1234,5'), 1234.5);
      expect(parseValorBr('1234.56'), 1234.56);
      expect(parseValorBr('R\$ 200'), 200);
      expect(parseValorBr(' 50 '), 50);
    });

    test('arredonda para centavos', () {
      expect(parseValorBr('10,999'), 11.0);
    });

    test('rejeita vazio, zero, negativo e lixo', () {
      for (final t in ['', '  ', '0', '0,00', '-5', 'abc', ',', '1,2,3x']) {
        expect(parseValorBr(t), isNull, reason: '"$t"');
      }
    });
  });

  group('descreverRegra', () {
    test('descreve cada tipo', () {
      expect(
        descreverRegra({'tipoEvento': 'SALDO_MINIMO', 'valorLimite': '100'}),
        contains('Saldo abaixo de'),
      );
      expect(
        descreverRegra({'tipoEvento': 'TRANSACAO_GRANDE', 'valorLimite': '500.00'}),
        contains('Transação acima de'),
      );
      expect(
        descreverRegra({
          'tipoEvento': 'DESPESA_CATEGORIA',
          'valorLimite': '200',
          'categoria': {'nome': 'Lazer'},
        }),
        contains('Gasto em Lazer acima de'),
      );
    });
  });

  group('RegrasAlertaNotifier', () {
    test('carregar traz as regras', () async {
      final n = RegrasAlertaNotifier(_FakeRepo(regras: [_regra(1), _regra(2)]));
      await n.carregar();
      expect(n.state.regras, hasLength(2));
      expect(n.state.isLoading, isFalse);
      n.dispose();
    });

    test('alternar atualiza na hora e envia só "ativa"', () async {
      final repo = _FakeRepo(regras: [_regra(1)]);
      final n = RegrasAlertaNotifier(repo);
      await n.carregar();

      final erro = await n.alternar(1, ativa: false);

      expect(erro, isNull);
      expect(n.state.regras.single['ativa'], isFalse);
      expect(repo.atualizadas[1], {'ativa': false});
      n.dispose();
    });

    test('alternar desfaz a mudança se o servidor recusar', () async {
      final repo = _FakeRepo(regras: [_regra(1)]);
      final n = RegrasAlertaNotifier(repo);
      await n.carregar();
      repo.falhar = true;

      final erro = await n.alternar(1, ativa: false);

      expect(erro, 'Erro no servidor');
      expect(n.state.regras.single['ativa'], isTrue);
      n.dispose();
    });

    test('excluir remove da lista', () async {
      final repo = _FakeRepo(regras: [_regra(1), _regra(2)]);
      final n = RegrasAlertaNotifier(repo);
      await n.carregar();

      expect(await n.excluir(1), isNull);

      expect(n.state.regras.map((r) => r['id']), [2]);
      expect(repo.excluidas, [1]);
      n.dispose();
    });

    test('excluir mantém a regra se o servidor recusar', () async {
      final repo = _FakeRepo(regras: [_regra(1)]);
      final n = RegrasAlertaNotifier(repo);
      await n.carregar();
      repo.falhar = true;

      expect(await n.excluir(1), isNotNull);
      expect(n.state.regras, hasLength(1));
      n.dispose();
    });

    test('salvar sem id cria, com id atualiza, e devolve o erro do servidor', () async {
      final repo = _FakeRepo();
      final n = RegrasAlertaNotifier(repo);

      expect(await n.salvar(dados: {'canal': 'PUSH'}), isNull);
      expect(repo.criadas, hasLength(1));

      expect(await n.salvar(id: 7, dados: {'canal': 'ALEXA'}), isNull);
      expect(repo.atualizadas[7], {'canal': 'ALEXA'});

      repo.falhar = true;
      expect(await n.salvar(dados: {}), 'Informe um valor limite maior que zero.');
      n.dispose();
    });
  });

  group('formulário', () {
    final categorias = [
      {'id': 1, 'nome': 'Lazer', 'tipo': 'DESPESA', 'icone': '🎮'},
      {'id': 2, 'nome': 'Renda', 'tipo': 'RECEITA', 'icone': '💰'},
    ];

    Future<_FakeRepo> abrir(WidgetTester tester, {Map<String, dynamic>? regra}) async {
      final repo = _FakeRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            regrasAlertaRepositoryProvider.overrideWithValue(repo),
            categoriasProvider.overrideWith((ref) async => categorias),
          ],
          child: MaterialApp(home: RegraAlertaFormScreen(regra: regra)),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('sem valor não salva e mostra o erro', (tester) async {
      final repo = await abrir(tester);

      await tester.tap(find.text('Criar regra'));
      await tester.pumpAndSettle();

      expect(find.text('Informe um valor maior que zero'), findsOneWidget);
      expect(repo.criadas, isEmpty);
    });

    testWidgets('cria transação grande com o valor em formato brasileiro', (tester) async {
      final repo = await abrir(tester);

      await tester.enterText(find.byType(TextFormField), '1.234,50');
      await tester.tap(find.text('Criar regra'));
      await tester.pumpAndSettle();

      expect(repo.criadas.single, {
        'tipoEvento': 'TRANSACAO_GRANDE',
        'valorLimite': 1234.5,
        'canal': 'PUSH',
      });
    });

    testWidgets('despesa por categoria exige escolher a categoria', (tester) async {
      final repo = await abrir(tester);

      await tester.tap(find.byType(DropdownButtonFormField<TipoRegra>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Despesa por categoria').last);
      await tester.pumpAndSettle();

      // só categorias de despesa são oferecidas
      expect(find.text('Categoria'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '200');
      await tester.tap(find.text('Criar regra'));
      await tester.pumpAndSettle();

      expect(find.text('Escolha a categoria'), findsOneWidget);
      expect(repo.criadas, isEmpty);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(find.textContaining('Renda'), findsNothing);
      await tester.tap(find.textContaining('Lazer').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Criar regra'));
      await tester.pumpAndSettle();

      expect(repo.criadas.single, {
        'tipoEvento': 'DESPESA_CATEGORIA',
        'valorLimite': 200.0,
        'canal': 'PUSH',
        'categoriaId': 1,
      });
    });

    testWidgets('editar preenche os campos e atualiza a regra', (tester) async {
      final repo = await abrir(tester, regra: {..._regra(9), 'valorLimite': '750.00', 'canal': 'AMBOS'});

      expect(find.text('Editar regra'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '750,00'), findsOneWidget);

      await tester.tap(find.text('Salvar alterações'));
      await tester.pumpAndSettle();

      expect(repo.atualizadas[9], {
        'tipoEvento': 'TRANSACAO_GRANDE',
        'valorLimite': 750.0,
        'canal': 'AMBOS',
      });
    });
  });
}
