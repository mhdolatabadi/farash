import 'package:flutter/material.dart';
import 'package:farash/core/widgets/app_loading_screen.dart';
import 'package:farash/features/auth/application/auth_controller.dart';
import 'package:farash/features/auth/presentation/sign_in_screen.dart';

/// Restores the saved session once, then shows sign-in or [signedIn].
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.controller, required this.signedIn});

  final AuthController controller;

  /// Builds the app for the signed-in account.
  final WidgetBuilder signedIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.controller.restore();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return switch (controller.status) {
          AuthStatus.restoring => const AppLoadingScreen(),
          AuthStatus.restoreFailed => _RestoreFailedScreen(
            onRetry: controller.restore,
          ),
          AuthStatus.signedOut => SignInScreen(controller: controller),
          AuthStatus.signedIn => widget.signedIn(context),
        };
      },
    );
  }
}

class _RestoreFailedScreen extends StatelessWidget {
  const _RestoreFailedScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('بازیابی ورود قبلی ممکن نشد'),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
