import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.apiClient,
    required this.onAuthenticated,
  });

  final ApiClient apiClient;
  final ValueChanged<AuthSession> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  var _registerMode = false;
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final session = _registerMode
          ? await widget.apiClient.register(
              email: _email.text,
              password: _password.text,
            )
          : await widget.apiClient.login(
              email: _email.text,
              password: _password.text,
            );
      if (!mounted) return;
      widget.onAuthenticated(session);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = _registerMode ? 'ساخت حساب فراش' : 'ورود به فراش';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: colors.primary,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'کارها، پروژه‌ها و برنامه‌ریزی‌هایت را خصوصی و همگام نگه دار.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'ایمیل',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (!email.contains('@')) {
                                return 'ایمیل را درست وارد کنید.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: true,
                            textDirection: TextDirection.ltr,
                            textInputAction: TextInputAction.done,
                            autofillHints: _registerMode
                                ? const [AutofillHints.newPassword]
                                : const [AutofillHints.password],
                            onFieldSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              labelText: 'رمز عبور',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                            validator: (value) {
                              final password = value ?? '';
                              if (password.length < 8 || password.length > 72) {
                                return 'رمز عبور باید بین ۸ تا ۷۲ کاراکتر باشد.';
                              }
                              return null;
                            },
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.error),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? const SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_registerMode ? 'ثبت‌نام' : 'ورود'),
                          ),
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () {
                                    setState(() {
                                      _registerMode = !_registerMode;
                                      _error = null;
                                    });
                                  },
                            child: Text(
                              _registerMode
                                  ? 'حساب دارم؛ وارد شوم'
                                  : 'حساب ندارم؛ ثبت‌نام کنم',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
