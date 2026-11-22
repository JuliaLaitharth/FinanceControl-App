import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';

/// Redefinição de senha com o código recebido por e-mail (vale 30 minutos, uso único).
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _confirmaCtrl = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _senhaCtrl.dispose();
    _confirmaCtrl.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final erro = await ref
        .read(authProvider.notifier)
        .redefinirSenha(codigo: _codigoCtrl.text.trim(), novaSenha: _senhaCtrl.text);
    if (!mounted) return;
    if (erro == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha redefinida. Faça login com a nova senha.')),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      setState(() {
        _enviando = false;
        _erro = erro;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Redefinir senha')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Informe o código que enviamos por e-mail e escolha a nova senha.'),
                const SizedBox(height: 24),
                if (_erro != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_erro!),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _codigoCtrl,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]'))],
                  decoration: const InputDecoration(labelText: 'Código (ex.: ABCD-EFGH)'),
                  validator: (v) =>
                      (v ?? '').replaceAll(RegExp(r'[\s-]'), '').length < 8 ? 'Informe o código completo' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _senhaCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Nova senha'),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.length < 8) return 'Mínimo 8 caracteres';
                    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
                      return 'Use letras e números';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmaCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirmar nova senha'),
                  validator: (v) => v != _senhaCtrl.text ? 'As senhas não conferem' : null,
                  onFieldSubmitted: (_) => _salvar(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _enviando ? null : _salvar,
                  child: _enviando
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Redefinir senha'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
