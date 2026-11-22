import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/regras_alerta_provider.dart';
import '../regra_alerta_modelo.dart';
import 'regra_alerta_form_screen.dart';

/// Lista as regras de alerta do usuário: ligar/desligar, editar e excluir.
class RegrasAlertaScreen extends ConsumerStatefulWidget {
  const RegrasAlertaScreen({super.key});

  @override
  ConsumerState<RegrasAlertaScreen> createState() => _RegrasAlertaScreenState();
}

class _RegrasAlertaScreenState extends ConsumerState<RegrasAlertaScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(regrasAlertaProvider.notifier).carregar());
  }

  void _aviso(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _abrirFormulario([Map<String, dynamic>? regra]) async {
    final salvou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RegraAlertaFormScreen(regra: regra)),
    );
    if (salvou == true) {
      _aviso(regra == null ? 'Regra criada.' : 'Regra atualizada.');
    }
  }

  Future<void> _confirmarExclusao(Map<String, dynamic> regra) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir regra'),
        content: Text('Excluir "${descreverRegra(regra)}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    final erro = await ref.read(regrasAlertaProvider.notifier).excluir(regra['id'] as int);
    _aviso(erro ?? 'Regra excluída.');
  }

  Future<void> _alternar(Map<String, dynamic> regra, bool ativa) async {
    final erro = await ref
        .read(regrasAlertaProvider.notifier)
        .alternar(regra['id'] as int, ativa: ativa);
    if (erro != null) _aviso(erro);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(regrasAlertaProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Regras de alerta')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nova regra'),
      ),
      body: Builder(
        builder: (_) {
          if (state.isLoading && state.regras.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.errorMessage != null && state.regras.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: cs.error),
                    const SizedBox(height: 12),
                    Text(state.errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref.read(regrasAlertaProvider.notifier).carregar(),
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (state.regras.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rule_outlined, size: 64, color: cs.outline),
                    const SizedBox(height: 16),
                    const Text('Nenhuma regra de alerta', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      'Crie uma regra para ser avisado sobre saldo baixo, '
                      'transações grandes ou gastos por categoria.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(regrasAlertaProvider.notifier).carregar(),
            child: ListView.separated(
              // espaço para o botão flutuante não cobrir o último item
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: state.regras.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final regra = state.regras[i];
                final ativa = regra['ativa'] as bool? ?? true;
                final tipo = TipoRegra.de(regra['tipoEvento'] as String?);
                final canal = CanalRegra.de(regra['canal'] as String?);

                return ListTile(
                  leading: Icon(
                    switch (tipo) {
                      TipoRegra.saldoMinimo => Icons.account_balance_wallet_outlined,
                      TipoRegra.transacaoGrande => Icons.payments_outlined,
                      TipoRegra.despesaCategoria => Icons.category_outlined,
                      TipoRegra.pixRecebido => Icons.arrow_downward,
                      TipoRegra.pixEnviado => Icons.arrow_upward,
                    },
                    color: ativa ? cs.primary : cs.outline,
                  ),
                  title: Text(
                    descreverRegra(regra),
                    style: TextStyle(color: ativa ? null : cs.outline),
                  ),
                  subtitle: Text('${tipo.titulo} · ${canal.rotulo}'),
                  onTap: () => _abrirFormulario(regra),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(value: ativa, onChanged: (v) => _alternar(regra, v)),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: cs.error),
                        tooltip: 'Excluir regra',
                        onPressed: () => _confirmarExclusao(regra),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
