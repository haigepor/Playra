/// Account authentication for CliCli. Credentials are never persisted.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../../services/storage/storage.dart';
import 'clicli_config.dart';
import '../core/media_source.dart';

typedef CliCliAuthCall =
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic> payload,
    );

/// Session storage must protect access and refresh tokens as sensitive data.
abstract class CliCliSessionStore {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> session);
  Future<void> clear();
}

/// Uses the application's existing settings box; its contents are not encrypted.
class CliCliSettingsSessionStore implements CliCliSessionStore {
  static const _key = 'clicli.auth.session.v1';
  @override
  Future<Map<String, dynamic>?> load() async {
    final value = GStorage.settings.get(_key);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  Future<void> save(Map<String, dynamic> session) =>
      GStorage.settings.put(_key, session);
  @override
  Future<void> clear() => GStorage.settings.delete(_key);
}

class CliCliAuth {
  CliCliAuth(
    this._call, {
    CliCliSessionStore? store,
    this.account = const String.fromEnvironment('CLICLI_ACCOUNT'),
    this.password = const String.fromEnvironment('CLICLI_PASSWORD'),
  }) : _store = store ?? CliCliSettingsSessionStore();

  final CliCliAuthCall _call;
  final CliCliSessionStore _store;
  final String account;
  final String password;
  Map<String, dynamic>? _session;
  Future<void>? _initializing;
  Future<bool>? _refreshing;

  bool get configured => account.isNotEmpty && password.isNotEmpty;
  String? get token => _session?['token'] as String?;

  /// Loads a matching saved session or signs in with compile-time credentials.
  Future<void> initialize() {
    if (!configured) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  Future<void> _initialize() async {
    if (token != null) return;
    final saved = await _store.load();
    if (saved != null &&
        saved['account'] == account &&
        saved['token'] is String &&
        (saved['token'] as String).isNotEmpty &&
        saved['refreshToken'] is String &&
        (saved['refreshToken'] as String).isNotEmpty) {
      _session = saved;
      return;
    }
    await login();
  }

  /// Login errors intentionally do not include server messages or credentials.
  Future<void> login() async {
    final keyData = await _call(
      '${CliCliConfig.apiPrefix}/auth/encryptKey',
      {},
    );
    final pem = keyData['publicKey'];
    if (pem is! String || pem.isEmpty) {
      throw const FormatException('Invalid public key');
    }
    final encrypted = _encryptPassword(pem, password);
    final data = await _call('${CliCliConfig.apiPrefix}/auth/login', {
      'account': account,
      'password': encrypted,
      'deviceId': CliCliConfig.deviceId,
      'deviceName': 'Pixel 6',
      'accountType': 'email',
    });
    await _save(data);
  }

  /// A stale token is checked again so delayed failures cannot rotate twice.
  Future<bool> refresh(String? staleToken) {
    if (staleToken != null && token != staleToken) {
      return Future.value(token != null);
    }
    final running = _refreshing;
    if (running != null) return running;
    final future = _doRefresh().whenComplete(() => _refreshing = null);
    _refreshing = future;
    return future;
  }

  Future<bool> _doRefresh() async {
    final refreshToken = _session?['refreshToken'];
    if (refreshToken is! String || refreshToken.isEmpty) return false;
    try {
      final data = await _call(CliCliConfig.pathRefreshToken, {
        'deviceId': CliCliConfig.deviceId,
        'refreshToken': refreshToken,
      });
      await _save(data, previous: _session);
      return true;
    } on MediaSourceException catch (error) {
      if (configured &&
          (error.code == 401 || error.code == 4012 || error.code == 4013)) {
        await login();
        return true;
      }
      rethrow;
    }
  }

  Future<void> _save(
    Map<String, dynamic> data, {
    Map<String, dynamic>? previous,
  }) async {
    final access = data['token'];
    final refresh = data['refreshToken'] ?? previous?['refreshToken'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const FormatException('Invalid authentication response');
    }
    final session = <String, dynamic>{
      'account': account,
      'token': access,
      'refreshToken': refresh,
      if (data['expireTime'] != null) 'expireTime': data['expireTime'],
      if (data['refreshExpireTime'] != null)
        'refreshExpireTime': data['refreshExpireTime'],
    };
    // Publish the rotated token even if persistence fails, avoiding reuse of the
    // now-invalid refresh token; surface the storage failure to the caller.
    _session = session;
    await _store.save(session);
  }

  Future<void> clear() async {
    _session = null;
    await _store.clear();
  }
}

// X.509 SubjectPublicKeyInfo (RSA) and RSAES-PKCS1-v1_5.
String _encryptPassword(String pem, String password) {
  final der = base64.decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''));
  final outer = _Der(der).read(0x30);
  outer.read(0x30); // algorithm identifier
  final bits = outer.readBytes(0x03);
  if (bits.isEmpty || bits.first != 0) {
    throw const FormatException('Invalid RSA key');
  }
  final rsa = _Der(bits.sublist(1)).read(0x30);
  final modulusBytes = rsa.readBytes(0x02);
  final exponentBytes = rsa.readBytes(0x02);
  BigInt integer(List<int> bytes) =>
      bytes.fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));
  final modulus = integer(modulusBytes);
  final exponent = integer(exponentBytes);
  final size = (modulus.bitLength + 7) ~/ 8;
  final message = utf8.encode(password);
  if (size < 11 || message.length > size - 11 || exponent <= BigInt.one) {
    throw const FormatException('Invalid RSA key or password length');
  }
  final random = Random.secure();
  final block = Uint8List(size)..[1] = 2;
  final separator = size - message.length - 1;
  for (var i = 2; i < separator; i++) {
    block[i] = random.nextInt(255) + 1;
  }
  block.setRange(separator + 1, size, message);
  var ciphertext = integer(block).modPow(exponent, modulus);
  final result = Uint8List(size);
  for (var i = size - 1; i >= 0; i--) {
    result[i] = (ciphertext & BigInt.from(255)).toInt();
    ciphertext >>= 8;
  }
  return base64.encode(result);
}

class _Der {
  _Der(this.bytes);
  final List<int> bytes;
  int offset = 0;
  _Der read(int tag) => _Der(readBytes(tag));
  List<int> readBytes(int tag) {
    if (offset + 2 > bytes.length || bytes[offset++] != tag) {
      throw const FormatException('Invalid DER');
    }
    var length = bytes[offset++];
    if ((length & 0x80) != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || offset + count > bytes.length) {
        throw const FormatException('Invalid DER length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[offset++];
      }
    }
    if (offset + length > bytes.length) {
      throw const FormatException('Invalid DER length');
    }
    final result = bytes.sublist(offset, offset + length);
    offset += length;
    return result;
  }
}
