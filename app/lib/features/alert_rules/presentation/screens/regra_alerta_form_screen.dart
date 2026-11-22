import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../accounts/data/accounts_repository.dart';
import '../../../transactions/presentation/providers/transacoes_provider.dart';
import '../providers/regras_alerta_provider.dart';
import '../regra_alerta_modelo.dart';

/// Formulário de criação/edição. Com [regra] preenche os campos e edita.
class RegraAlertaFormScreen extends ConsumerStatefulWidget {
  const RegraAlertaFormScreen({super.key, this.regra});

  final Map<String, dynamic>? regra;

  @override
  ConsumerState<RegraAlertaFormScreen> createState() => _RegraAlertaFormScreenState();
}

class _RegraAlertaFormScreenState extends ConsumerState<RegraAlertaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _valorCtrl;
  late TipoRegra _tipo;
  late CanalRegra _canal;
  int? _categoriaId;
  int? _contaId;
  List<Map<String, dynamic>> _contas = [];
  bool _salvando = false;

  bool get _editando => widget.regra != null;

  @override
  void initState() {
    super.initState();
    final r = widget.regra;
    _tipo = TipoRegra.de(r?['tipoEvento'] as String?);
    _canal = CanalRegra.de(r?['canal'] as String?);
    _categoriaId = r?['categoriaId'] as int?;
    _contaId = r?['contaId'] as int?;
    _carregarContas();
    final limite = num.tryParse('${r?['valorLimite'] ?? ''}');
    _valorCtrl = TextEditingController(
      text: limite == null ? '' : limite.toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  Future<void> _carregarContas() async {
    try {
      final todas = await ref.read(accountsRepositoryProvider).listarContas();
      if (!mounted) return;
      setState(() {
        _contas = todas
            .cast<Map<String, dynamic>>()
            .where((c) => c['tipo'] != 'CREDIT') // cartão tem saldo negativo por natureza
            .toList();
      });
    } catch (_) {}
  }

  String _rotuloConta(Map<String, dynamic> c) {
    final banco = (c['consentimento']?['instituicao']?['nome'] ?? 'Conta') as String;
    final num = c['numeroMascarado'] ?? c['id'];
    return '$banco · $num';
  }

  @override
  void dispose() {
    _valorCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    final erro = await ref.read(regrasAlertaProvider.notifier).salvar(
      id: widget.regra?['id'] as int?,
      dados: {
        'tipoEvento': _tipo.codigo,
        'valorLimite': parseValorBr(_valorCtrl.text),
        if (_tipo == TipoRegra.saldoMinimo) 'contaId': _contaId,
        'canal': _canal.codigo,
        if (_tipo == TipoRegra.despesaCategoria) 'categoriaId': _categoriaId,
      },
    );
    if (!mounted) return;

    if (erro == null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final categoriasAsync = ref.watch(categoriasProvider);

    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar regra' : 'Nova regra')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<TipoRegra>(
              initialValue: _tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo de alerta',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in TipoRegra.values)
                  DropdownMenuItem(value: t, child: Text(t.titulo)),
              ],
              onChanged: (t) => setState(() => _tipo = t ?? _tipo),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
              child: Text(
                _tipo.descricao,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),

            TextFormField(
              controller: _valorCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: _tipo.ehPix ? 'Valor mínimo (opcional)' : 'Valor limite',
                prefixText: 'R\$ ',
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (_tipo.ehPix && (v ?? '').trim().isEmpty) return null;
                return parseValorBr(v ?? '') == null ? 'Informe um valor maior que zero' : null;
              },
            ),
            const SizedBox(height: 16),

            if (_tipo == TipoRegra.saldoMinimo) ...[
              DropdownButtonFormField<int>(
                initialValue: _contas.any((c) => c['id'] == _contaId) ? _contaId : null,
                decoration: const InputDecoration(
                  labelText: 'Conta',
                  helperText: 'Um alerta de saldo mínimo por conta.',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in _contas)
                    DropdownMenuItem(value: c['id'] as int, child: Text(_rotuloConta(c))),
                ],
                onChanged: (id) => setState(() => _contaId = id),
                validator: (id) => id == null ? 'Escolha a conta' : null,
              ),
              const SizedBox(height: 16),
            ],

            if (_tipo == TipoRegra.despesaCategoria) ...[
              categoriasAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => Text(
                  'Não foi possível carregar as categorias.',
                  style: TextStyle(color: cs.error),
                ),
                data: (cats) {
                  final despesas = cats
                      .cast<Map<String, dynamic>>()
                      .where((c) => c['tipo'] == 'DESPESA')
                      .toList();
                  return DropdownButtonFormField<int>(
                    initialValue: despesas.any((c) => c['id'] == _categoriaId)
                        ? _categoriaId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Categoria',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in despesas)
                        DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text('${c['icone'] ?? ''} ${c['nome']}'.trim()),
                        ),
                    ],
                    onChanged: (id) => setState(() => _categoriaId = id),
                    validator: (id) => id == null ? 'Escolha a categoria' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            Text('Avisar por', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<CanalRegra>(
              segments: [
                for (final c in CanalRegra.values)
                  ButtonSegment(value: c, label: Text(c.rotulo)),
              ],
              selected: {_canal},
              onSelectionChanged: (s) => setState(() => _canal = s.first),
            ),
            const SizedBox(height: 32),

            FilledButton(
              onPressed: _salvando ? null : _salvar,
              child: _salvando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_editando ? 'Salvar alterações' : 'Criar regra'),
            ),
          ],
        ),
      ),
    );
  }
}
