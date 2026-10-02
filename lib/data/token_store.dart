import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class StoredSession {
  const StoredSession(this.token, this.account);
  final String token;
  final Account account;
}

class TokenStore {
  const TokenStore();
  static const _storage = FlutterSecureStorage();
  Future<StoredSession?> read() async {
    final value = await _storage.read(key: 'zvuk_session');
    if (value == null) return null;
    final data = jsonDecode(value) as Map<String, dynamic>;
    return StoredSession(
      data['token'] as String,
      Account.fromJson(data['account']),
    );
  }

  // One secure entry keeps the token and its account identity consistent even
  // if the app exits between secure-storage and SQLite writes.
  Future<void> write(String token, Account account) => _storage.write(
    key: 'zvuk_session',
    value: jsonEncode({'token': token, 'account': account.toJson()}),
  );
}
