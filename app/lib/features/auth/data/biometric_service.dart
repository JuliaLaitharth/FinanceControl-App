import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Isola o `local_auth` e a preferência local de biometria, para que o resto
/// do app (e os testes) não dependam de plugins nativos.
abstract class BiometricService {
  /// O aparelho tem biometria cadastrada e utilizável?
  Future<bool> disponivel();

  /// Pede a biometria ao usuário. `false` em falha, cancelamento ou erro.
  Future<bool> autenticar(String motivo);

  /// Preferência guardada localmente (permite decidir o bloqueio offline).
  Future<bool> lerAtiva();
  Future<void> salvarAtiva(bool ativa);
}

class LocalBiometricService implements BiometricService {
  LocalBiometricService({
    LocalAuthentication? auth,
    FlutterSecureStorage? storage,
  })  : _auth = auth ?? LocalAuthentication(),
        _storage = storage ?? const FlutterSecureStorage();

  static const _keyAtiva = 'biometria_ativa';

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  @override
  Future<bool> disponivel() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> autenticar(String motivo) async {
    try {
      return await _auth.authenticate(
        localizedReason: motivo,
        // Só biometria: o fallback do app é a senha (RF01), não o PIN do aparelho.
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> lerAtiva() async {
    try {
      return await _storage.read(key: _keyAtiva) == 'true';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> salvarAtiva(bool ativa) async {
    try {
      await _storage.write(key: _keyAtiva, value: ativa.toString());
    } catch (_) {}
  }
}

final biometricServiceProvider =
    Provider<BiometricService>((ref) => LocalBiometricService());
