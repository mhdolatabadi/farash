import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/auth/application/auth_controller.dart';
import 'package:farash/features/auth/data/token_store.dart';

import 'support/fake_auth_api.dart';

void main() {
  test('without a saved token, restore signs out', () async {
    final auth = AuthController(
      api: FakeAuthApi(),
      tokenStore: MemoryTokenStore(),
    );

    await auth.restore();

    expect(auth.status, AuthStatus.signedOut);
    expect(auth.token, isNull);
  });

  test('restore keeps a valid saved token', () async {
    final auth = AuthController(
      api: FakeAuthApi(),
      tokenStore: MemoryTokenStore('token-a@example.com'),
    );

    await auth.restore();

    expect(auth.status, AuthStatus.signedIn);
    expect(auth.user!.email, 'a@example.com');
    expect(auth.token, 'token-a@example.com');
  });

  test('restore discards a rejected token', () async {
    final tokens = MemoryTokenStore('expired');
    final auth = AuthController(api: FakeAuthApi(), tokenStore: tokens);

    await auth.restore();

    expect(auth.status, AuthStatus.signedOut);
    expect(await tokens.read(), isNull);
  });

  test(
    'a network failure during restore keeps the token for a retry',
    () async {
      final tokens = MemoryTokenStore('token-a@example.com');
      final api = FakeAuthApi(meError: const ApiException('offline'));
      final auth = AuthController(api: api, tokenStore: tokens);

      await auth.restore();

      expect(auth.status, AuthStatus.restoreFailed);
      expect(await tokens.read(), 'token-a@example.com');

      api.meError = null;
      await auth.restore();
      expect(auth.status, AuthStatus.signedIn);
    },
  );

  test('register saves the session; logout clears it', () async {
    final tokens = MemoryTokenStore();
    final auth = AuthController(api: FakeAuthApi(), tokenStore: tokens);

    await auth.register('  a@example.com ', 'password1');

    expect(auth.status, AuthStatus.signedIn);
    expect(auth.user!.email, 'a@example.com');
    expect(await tokens.read(), 'token-a@example.com');

    await auth.logout();

    expect(auth.status, AuthStatus.signedOut);
    expect(auth.token, isNull);
    expect(await tokens.read(), isNull);
  });

  test('a failed login leaves the user signed out', () async {
    final auth = AuthController(
      api: FakeAuthApi(accounts: {'a@example.com': 'password1'}),
      tokenStore: MemoryTokenStore(),
    );
    await auth.restore();

    await expectLater(
      auth.login('a@example.com', 'wrong-password'),
      throwsA(isA<ApiException>()),
    );
    expect(auth.status, AuthStatus.signedOut);
  });
}
