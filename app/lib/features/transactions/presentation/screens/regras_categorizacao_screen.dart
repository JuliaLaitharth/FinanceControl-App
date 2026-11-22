import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/transacoes_repository.dart';
import '../providers/transacoes_provider.dart';

/// Regras do usuário: quando a descrição contém a palavra, a transação
/// recebe a categoria escolhida (aplicado nas próximas sincronizações).
class RegrasCategorizacaoScreen extends ConsumerStatefulWidget {
  const RegrasCategorizacaoScreen({super.key});

  @override
  ConsumerState<RegrasCategorizacaoScreen> createState() => _RegrasCategorizacaoScreenState();
}

class _RegrasCategorizacaoScreenState extends ConsumerState<RegrasCategorizacaoScreen> {
  List<Map<String, dynamic>> _regras = [];
  bool _carregando = true;
  String? _erro;

  TransacoesRepository get _repo => ref.read(transacoesRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await _repo.listarRegrasCategorizacao();
      if (mounted) setState(() => _regras = r);
    } catch (_) {
      if (mounted) setState(() => _erro = 'Não foi possível carregar as regras.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _aviso(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _excluir(Map<String, dynamic> regra) async {
    try {
      await _repo.excluirRegraCategorizacao(regra['id'] as int);
      await _carregar();
    } catch (_) {
      if (mounted) _aviso('Não foi possível excluir a regra.');
    }
  }

  Future<void> _nova() async {
    final categorias = (ref.read(categoriasProvider).valueOrNull ?? []).cast<Map<String, dynamic>>();
    if (categorias.isEmpty) {
      _aviso('Categorias indisponíveis no momento.');
      return;
    }
    final palavraCtrl = TextEditingController();
    int? categoriaId;
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nova regra'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: palavraCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Palavra na descrição',
                    helperText: 'Ex.: uber, padaria',
                  ),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Mínimo 2 caracteres' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: categoriaId,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: categorias
                      .map((c) => DropdownMenuItem<int>(
                            value: c['id'] as int,
                            child: Text('${c['icone'] ?? ''} ${c['nome']}'),
                          ))
                      .toList(),
                  onChanged: (v) => setD(() => categoriaId = v),
                  validator: (v) => v == null ? 'Escolha a categoria' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true) Navigator.pop(ctx, true);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || categoriaId == null) return;

    try {
      await _repo.criarRegraCategorizacao(palavraCtrl.text.trim(), categoriaId!);
      await _carregar();
    } catch (_) {
      if (mounted) _aviso('Não foi possível salvar a regra (a palavra pode já existir).');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Regras de categorização')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nova,
        icon: const Icon(Icons.add),
        label: const Text('Nova regra'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : _regras.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhuma regra. Crie uma para que descrições com certa palavra '
                          'entrem sempre na categoria escolhida (vale nas próximas sincronizações).',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _regras.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = _regras[i];
                        return ListTile(
                          title: Text('"${r['palavra']}"'),
                          subtitle: Text('→ ${(r['categoria'] as Map?)?['nome'] ?? ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Excluir',
                            onPressed: () => _excluir(r),
                          ),
                        );
                      },
                    ),
    );
  }
}
