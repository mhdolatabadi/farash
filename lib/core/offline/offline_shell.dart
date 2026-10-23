import 'package:flutter/material.dart';

import 'offline_read_cache.dart';

class OfflineShell extends StatefulWidget {
  const OfflineShell({
    super.key,
    required this.cache,
    required this.onReconnect,
    required this.child,
  });
  final OfflineReadCache cache;
  final Future<void> Function() onReconnect;
  final Widget child;

  @override
  State<OfflineShell> createState() => _OfflineShellState();
}

class _OfflineShellState extends State<OfflineShell> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.onReconnect();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.cache,
    builder: (context, _) {
      if (!widget.cache.isOffline) return widget.child;
      final colors = Theme.of(context).colorScheme;
      return Material(
        color: colors.surface,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _failed
                            ? 'اتصال برقرار نشد؛ داده‌های ذخیره‌شده فقط برای مشاهده‌اند.'
                            : 'آفلاین؛ داده‌های ذخیره‌شده فقط برای مشاهده‌اند.',
                        style: TextStyle(color: colors.onSurface),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _retry,
                      icon: const Icon(Icons.refresh),
                      label: Text(_busy ? 'در حال اتصال…' : 'اتصال دوباره'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: widget.child,
              ),
            ),
          ],
        ),
      );
    },
  );
}
