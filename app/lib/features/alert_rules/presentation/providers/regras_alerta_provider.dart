import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/regras_alerta_repository.dart';

class RegrasAlertaState {
  const RegrasAlertaState({
    this.regras = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<Map<String, dynamic>> regras;
  final bool isLoading;
  final String? errorMessage;

  RegrasAlertaState copyWith({
    List<Map<String, dynamic>>? regras,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) =>
      RegrasAlertaState(
        regras: regras ?? this.regras,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class RegrasAlertaNotifier extends StateNotifier<RegrasAlertaState> {
  RegrasAlertaNotifier(this._repo) : super(const RegrasAlertaState());

  final RegrasAlertaRepository _repo;

  Future<void> carregar() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final regras = await _repo.listar();
      if (mounted) state = state.copyWith(regras: regras, isLoading: false);
    } catch (e) {
      if (mounted) state = state.copyWith(errorMessage: _parseError(e), isLoading: false);
    }
  }

  /// Cria (id nulo) ou atualiza uma regra. Retorna a mensagem de erro, ou `null` se deu certo.
  Future<String?> salvar({int? id, required Map<String, dynamic> dados}) async {
    try {
      if (id == null) {
        await _repo.criar(dados);
      } else {
        await _repo.atualizar(id, dados);
      }
      await carregar();
      return null;
    } catch (e) {
      return _parseError(e);
    }
  }

  /// Liga/desliga a regra. Atualiza a tela na hora e desfaz se o servidor recusar.
  Future<String?> alternar(int id, {required bool ativa}) async {
    final anterior = state.regras;
    state = state.copyWith(
      regras: [
        for (final r in anterior) r['id'] == id ? {...r, 'ativa': ativa} : r,
      ],
    );
    try {
      await _repo.atualizar(id, {'ativa': ativa});
      return null;
    } catch (e) {
      if (mounted) state = state.copyWith(regras: anterior);
      return _parseError(e);
    }
  }

  Future<String?> excluir(int id) async {
    try {
      await _repo.excluir(id);
      if (mounted) {
        state = state.copyWith(
          regras: state.regras.where((r) => r['id'] != id).toList(),
        );
      }
      return null;
    } catch (e) {
      return _parseError(e);
    }
  }

  String _parseError(Object e) {
    try {
      final dynamic data = (e as dynamic).response?.data; // ignore: avoid_dynamic_calls
      if (data is Map) {
        final msg = data['message'];
        if (msg is String) return msg;
        if (msg is List) return msg.join(', ');
      }
    } catch (_) {}
    return 'Ocorreu um erro. Tente novamente.';
  }
}

final regrasAlertaProvider =
    StateNotifierProvider<RegrasAlertaNotifier, RegrasAlertaState>(
  (ref) => RegrasAlertaNotifier(ref.watch(regrasAlertaRepositoryProvider)),
);
