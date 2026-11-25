import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../accounts/presentation/providers/accounts_provider.dart';
import '../../../accounts/presentation/screens/accounts_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Abre as contas conectadas e, ao voltar, recarrega o saldo.
  Future<void> _abrirContas(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AccountsScreen()),
    );
    ref.invalidate(saldoProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldoAsync = ref.watch(saldoProvider);
    final cs = Theme.of(context).colorScheme;
    final brl = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: const Text('FinanceControl'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_outlined),
            tooltip: 'Contas conectadas',
            onPressed: () => _abrirContas(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: () => ref.invalidate(saldoProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(saldoProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── Card de saldo total ────────────────────────────────────────
            Card(
              color: cs.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saldo total',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    saldoAsync.when(
                      loading: () => const SizedBox(
                        height: 40,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Text(
                        'Erro ao carregar saldo',
                        style: TextStyle(color: cs.error, fontSize: 24),
                      ),
                      data: (saldo) {
                        final total = (saldo['total'] as num?)?.toDouble() ?? 0;
                        return Text(
                          brl.format(total),
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    saldoAsync.whenOrNull(
                          data: (saldo) {
                            final sync = saldo['ultimaSincronizacao'];
                            if (sync == null) return const SizedBox.shrink();
                            final dt = DateTime.tryParse(sync.toString());
                            if (dt == null) return const SizedBox.shrink();
                            final semConexao = saldo['doCache'] == true ? 'Sem conexão · ' : '';
                            return Text(
                              '${semConexao}Atualizado: ${DateFormat('dd/MM/yy HH:mm', 'pt_BR').format(dt.toLocal())}',
                              style: TextStyle(
                                color: cs.onPrimaryContainer.withAlpha(180),
                                fontSize: 12,
                              ),
                            );
                          },
                        ) ??
                        const SizedBox.shrink(),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ─── Saldo por instituição ──────────────────────────────────────
            saldoAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
              data: (saldo) {
                final porInst =
                    saldo['porInstituicao'] as List<dynamic>? ?? [];
                if (porInst.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          const Icon(Icons.account_balance_outlined,
                              size: 56, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('Nenhuma conta conectada'),
                          const SizedBox(height: 8),
                          Text(
                            'Conecte seu banco para ver saldos e transações',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _abrirContas(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Conectar conta'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Por instituição',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ...porInst.map((inst) {
                      final m = inst as Map<String, dynamic>;
                      final nome = m['nome'] as String? ?? '';
                      final saldoInst =
                          (m['saldo'] as num?)?.toDouble() ?? 0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.account_balance_outlined),
                        title: Text(nome),
                        trailing: Text(
                          brl.format(saldoInst),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: saldoInst >= 0
                                ? Colors.green.shade700
                                : cs.error,
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
