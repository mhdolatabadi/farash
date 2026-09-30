import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/auth/data/auth_models.dart';

/// Keeps accounts in memory; tokens are `token-<email>`.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({Map<String, String>? accounts, this.meError})
    : accounts = accounts ?? {};

  /// email → password.
  final Map<String, String> accounts;

  /// Thrown by [me] instead of answering.
  Object? meError;

  @override
  Future<AuthSession> login(String email, String password) async {
    if (accounts[email] != password) {
      throw const ApiException(
        'unauthorized',
        statusCode: 401,
        code: 'invalid_credentials',
      );
    }
    return _session(email);
  }

  @override
  Future<AuthSession> register(String email, String password) async {
    if (accounts.containsKey(email)) {
      throw const ApiException(
        'conflict',
        statusCode: 409,
        code: 'email_taken',
      );
    }
    accounts[email] = password;
    return _session(email);
  }

  @override
  Future<AuthUser> me(String token) async {
    final error = meError;
    if (error != null) throw error;
    if (!token.startsWith('token-')) {
      throw const ApiException(
        'unauthorized',
        statusCode: 401,
        code: 'invalid_token',
      );
    }
    final email = token.substring('token-'.length);
    return AuthUser(id: 'id-$email', email: email);
  }

  AuthSession _session(String email) => AuthSession(
    token: 'token-$email',
    user: AuthUser(id: 'id-$email', email: email),
  );
}
