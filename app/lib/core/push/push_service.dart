import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notifications/data/notificacoes_repository.dart';

/// O push é opt-in: compile com `--dart-define=FCM_ENABLED=true` depois de colocar os arquivos
/// do Firebase no projeto (veja docs/INTEGRACOES.md). Sem isso, nada do Firebase é tocado — o
/// app roda normalmente e as notificações continuam aparecendo na aba Alertas.
const bool fcmHabilitado = bool.fromEnvironment('FCM_ENABLED');

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(ref.watch(notificacoesRepositoryProvider)),
);

class PushService {
  PushService(this._repo);

  final NotificacoesRepository _repo;
  bool _iniciado = false;
  StreamSubscription<String>? _subToken;
  StreamSubscription<RemoteMessage>? _subMensagem;

  /// Pede permissão, registra o token no backend e escuta mensagens com o app aberto.
  /// [aoReceber] recebe o texto da notificação (para atualizar a tela e avisar o usuário).
  /// Nunca lança: se o Firebase não estiver configurado, o push simplesmente fica desligado.
  Future<void> iniciar({void Function(String? titulo, String? corpo)? aoReceber}) async {
    if (!fcmHabilitado || _iniciado) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final fcm = FirebaseMessaging.instance;

      final permissao = await fcm.requestPermission();
      if (permissao.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push: permissão negada pelo usuário.');
        return;
      }
      _iniciado = true;

      // getToken/onTokenRefresh são marcados como obsoletos no pacote, mas devolvem o token de
      // registro FCM que o `messaging().send({ token })` do backend espera (o novo `onRegistered`
      // devolve outro identificador, para envio direto).
      // ignore: deprecated_member_use
      final token = await fcm.getToken();
      if (token != null) await _registrar(token);

      // O token pode ser trocado pelo Firebase; mantém o backend atualizado.
      // ignore: deprecated_member_use
      _subToken = fcm.onTokenRefresh.listen(_registrar);

      // Com o app aberto o sistema não mostra a notificação; repassa para a tela.
      _subMensagem = FirebaseMessaging.onMessage.listen((m) {
        aoReceber?.call(m.notification?.title, m.notification?.body);
      });
    } catch (e) {
      debugPrint('Push desligado (Firebase não configurado?): $e');
    }
  }

  Future<void> _registrar(String token) async {
    try {
      await _repo.registrarFcmToken(token);
    } catch (e) {
      debugPrint('Push: não foi possível registrar o token: $e');
    }
  }

  void parar() {
    _subToken?.cancel();
    _subMensagem?.cancel();
    _iniciado = false;
  }
}
