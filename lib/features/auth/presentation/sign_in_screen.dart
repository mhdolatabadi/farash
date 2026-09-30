import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/auth/application/auth_controller.dart';

const _minPasswordLength = 8;
const _maxPasswordBytes = 72;

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = false;
  bool _isBusy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isBusy || !_formKey.currentState!.validate()) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      if (_isRegistering) {
        await widget.controller.register(_email.text, _password.text);
      } else {
        await widget.controller.login(_email.text, _password.text);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  static String _messageFor(Object error) {
    if (error is! ApiException) return 'اتصال به سرور برقرار نشد.';
    return switch (error.code) {
      'invalid_credentials' => 'ایمیل یا رمز عبور درست نیست.',
      'email_taken' => 'با این ایمیل قبلاً حساب ساخته شده است.',
      'invalid_email' => 'ایمیل معتبر نیست.',
      'invalid_password' => 'رمز عبور باید ۸ تا ۷۲ کاراکتر باشد.',
      'rate_limited' => 'تلاش‌ها زیاد بود. کمی بعد دوباره امتحان کنید.',
      _ => error.message,
    };
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'رمز عبور را وارد کنید.';
    if (!_isRegistering) return null;
    if (value.length < _minPasswordLength) {
      return 'رمز عبور باید حداقل ۸ کاراکتر باشد.';
    }
    if (value.length > _maxPasswordBytes) {
      return 'رمز عبور حداکثر ۷۲ کاراکتر است.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          child: Image(
                            image: AssetImage('assets/icon/farash.png'),
                            width: 64,
                            height: 64,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _isRegistering ? 'ساخت حساب فراش' : 'ورود به فراش',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'کارها و برنامه‌هایتان، روی همهٔ دستگاه‌ها.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'ایمیل'),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        textDirection: TextDirection.ltr,
                        validator: (value) =>
                            value == null || !value.trim().contains('@')
                            ? 'ایمیل معتبر وارد کنید.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        decoration: InputDecoration(
                          labelText: 'رمز عبور',
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'نمایش رمز عبور'
                                : 'پنهان کردن رمز عبور',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        obscureText: _obscure,
                        autofillHints: [
                          _isRegistering
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        textDirection: TextDirection.ltr,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: _validatePassword,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _isBusy ? null : _submit,
                        child: _isBusy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_isRegistering ? 'ساخت حساب' : 'ورود'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _isBusy
                            ? null
                            : () => setState(() {
                                _isRegistering = !_isRegistering;
                                _error = null;
                              }),
                        child: Text(
                          _isRegistering
                              ? 'حساب دارید؟ وارد شوید'
                              : 'حساب ندارید؟ ثبت‌نام کنید',
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
    );
  }
}
