import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pluggy_connect/flutter_pluggy_connect.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/accounts_provider.dart';

/// Em debug, o widget lista também os conectores de sandbox (ex.: "Pluggy Bank").
/// Em release fica desligado; force com --dart-define=PLUGGY_SANDBOX=true.
const _kIncludeSandbox =
    bool.fromEnvironment('PLUGGY_SANDBOX', defaultValue: kDebugMode);

/// Abre o Pluggy Connect (SDK oficial) e, ao concluir, envia o itemId ao backend.
///
/// O widget devolve o resultado em `onSuccess({'item': {'id': ...}})`.
class ConnectAccountScreen extends ConsumerStatefulWidget {
  const ConnectAccountScreen({super.key});

  @override
  ConsumerState<ConnectAccountScreen> createState() =>
      _ConnectAccountScreenState();
}

class _ConnectAccountScreenState extends ConsumerState<ConnectAccountScreen> {
  String? _connectToken;
  String? _errorMsg;
  bool _registrando = false;
  bool _finalizado = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final token = await ref.read(accountsProvider.notifier).gerarConnectToken();
    if (!mounted) return;
    setState(() {
      _connectToken = token;
      _errorMsg =
          token == null ? 'Não foi possível iniciar a conexão bancária.' : null;
    });
  }

  void _aoConcluir(dynamic data) {
    final itemId = _extrairItemId(data);
    if (itemId == null) {
      _encerrar(false, 'Não foi possível identificar a conexão criada.');
      return;
    }
    _registrar(itemId);
  }

  String? _extrairItemId(dynamic data) {
    if (data is Map) {
      final item = data['item'];
      if (item is Map) {
        final id = item['id'];
        if (id is String && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  Future<void> _registrar(String itemId) async {
    if (_registrando || _finalizado || !mounted) return;
    setState(() => _registrando = true);

    final sucesso = await ref
        .read(accountsProvider.notifier)
        .registrarConsentimento(itemId);

    if (!mounted) return;
    if (sucesso) {
      _encerrar(true);
    } else {
      _encerrar(
        false,
        ref.read(accountsProvider).errorMessage ??
            'Não foi possível conectar a conta.',
      );
    }
  }

  void _aoFalhar(dynamic error) {
    final msg = error is Map ? error['message'] : null;
    _encerrar(
      false,
      msg is String && msg.isNotEmpty
          ? msg
          : 'Não foi possível conectar a conta.',
    );
  }

  /// Fecha a tela uma única vez, mesmo que o widget dispare vários eventos.
  void _encerrar(bool sucesso, [String? mensagem]) {
    if (_finalizado || !mounted) return;
    _finalizado = true;
    if (mensagem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
    }
    Navigator.pop(context, sucesso);
  }

  void _aoFechar() {
    // CLOSE também é emitido após o sucesso; só trata como cancelamento
    // se nada estiver em andamento.
    if (_registrando) return;
    _encerrar(false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar conta bancária'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _encerrar(false),
        ),
      ),
      body: Stack(
        children: [
          if (_errorMsg != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(_errorMsg!, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        setState(() => _errorMsg = null);
                        _iniciar();
                      },
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          else if (_connectToken != null)
            PluggyConnect(
              connectToken: _connectToken!,
              includeSandbox: _kIncludeSandbox,
              connectorTypes: const ['PERSONAL_BANK', 'BUSINESS_BANK', 'INVESTMENT'],
              onSuccess: _aoConcluir,
              onError: _aoFalhar,
              onClose: _aoFechar,
            )
          else
            const Center(child: CircularProgressIndicator()),
          if (_registrando)
            const ColoredBox(
              color: Color(0x88000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
