import 'package:finance_control/core/api/api_client.dart';
import 'package:finance_control/core/push/push_service.dart';
import 'package:finance_control/features/notifications/data/notificacoes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _RepoFalso extends NotificacoesRepository {
  _RepoFalso() : super(ApiClient());
  int tokens = 0;

  @override
  Future<void> registrarFcmToken(String token) async => tokens++;
}

void main() {
  test('sem FCM_ENABLED o push fica desligado e não toca no Firebase', () async {
    expect(fcmHabilitado, isFalse);
    final repo = _RepoFalso();
    var avisos = 0;
    await PushService(repo).iniciar(aoReceber: (_, __) => avisos++);
    expect(repo.tokens, 0);
    expect(avisos, 0);
  });
}
