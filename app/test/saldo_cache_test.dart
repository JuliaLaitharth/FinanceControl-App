import 'package:finance_control/core/api/api_client.dart';
import 'package:finance_control/features/accounts/data/accounts_repository.dart';
import 'package:finance_control/features/accounts/presentation/providers/accounts_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RepoFalso extends AccountsRepository {
  _RepoFalso({this.salvo, this.daApi}) : super(ApiClient());
  final Map<String, dynamic>? salvo;
  final Map<String, dynamic>? daApi; // null = sem internet

  @override
  Future<Map<String, dynamic>?> saldoDoCache() async => salvo;

  @override
  Future<Map<String, dynamic>> saldoConsolidado() async =>
      daApi ?? (throw Exception('sem internet'));
}

Future<List<AsyncValue<Map<String, dynamic>>>> _estados(_RepoFalso repo) async {
  final c = ProviderContainer(overrides: [accountsRepositoryProvider.overrideWithValue(repo)]);
  final estados = <AsyncValue<Map<String, dynamic>>>[];
  c.listen(saldoProvider, (_, v) => estados.add(v), fireImmediately: true);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  c.dispose();
  return estados;
}

void main() {
  test('sem internet mostra o saldo salvo, marcado como do cache', () async {
    final ultimo = (await _estados(_RepoFalso(salvo: {'total': 10}))).last;
    expect(ultimo.value, {'total': 10, 'doCache': true});
    expect(ultimo.hasError, isFalse);
  });

  test('com internet mostra o salvo e depois o da API', () async {
    final estados = await _estados(_RepoFalso(salvo: {'total': 10}, daApi: {'total': 25}));
    expect(estados.where((e) => e.hasValue).map((e) => e.value!['total']), [10, 25]);
  });

  test('sem internet e sem nada salvo mostra erro', () async {
    expect((await _estados(_RepoFalso())).last.hasError, isTrue);
  });
}
