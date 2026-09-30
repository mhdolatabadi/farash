import 'package:flutter/material.dart';
import 'package:farash/core/widgets/app_loading_screen.dart';

/// Shows [child] once the API answers its health check, with a retry screen
/// while it does not.
class BackendGate extends StatefulWidget {
  const BackendGate({
    super.key,
    required this.healthCheck,
    required this.child,
  });

  /// Null when no server address is configured.
  final Future<void> Function()? healthCheck;

  final Widget child;

  @override
  State<BackendGate> createState() => _BackendGateState();
}

class _BackendGateState extends State<BackendGate> {
  late Future<void>? _connection;

  @override
  void initState() {
    super.initState();
    _connection = widget.healthCheck?.call();
  }

  void _retry() {
    setState(() {
      _connection = widget.healthCheck?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_connection == null) return const _ConfigurationRequiredScreen();

    return FutureBuilder<void>(
      future: _connection,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoadingScreen();
        }
        if (snapshot.hasError) {
          return _BackendUnavailableScreen(onRetry: _retry);
        }
        return widget.child;
      },
    );
  }
}

class _ConfigurationRequiredScreen extends StatelessWidget {
  const _ConfigurationRequiredScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'برای اجرای فراش، آدرس سرور را با '
            '--dart-define=API_BASE_URL=https://todo.example.com تنظیم کنید.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _BackendUnavailableScreen extends StatelessWidget {
  const _BackendUnavailableScreen({required this.onRetry});

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
              Icon(
                Icons.cloud_off_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              const Text('اتصال به سرور برقرار نشد'),
              const SizedBox(height: 8),
              const Text(
                'اتصال اینترنت و آدرس سرور را بررسی کنید.',
                textAlign: TextAlign.center,
              ),
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
