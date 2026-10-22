import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'export_api.dart';
import 'export_saver.dart';

Future<void> showAccountExport(
  BuildContext context,
  ExportApi api,
  String Function() token, {
  ExportSaver saver = saveAccountExport,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      AccountExportDialog(api: api, token: token, saver: saver),
);

class AccountExportDialog extends StatefulWidget {
  const AccountExportDialog({
    super.key,
    required this.api,
    required this.token,
    this.saver = saveAccountExport,
  });

  final ExportApi api;
  final String Function() token;
  final ExportSaver saver;

  @override
  State<AccountExportDialog> createState() => _AccountExportDialogState();
}

class _AccountExportDialogState extends State<AccountExportDialog> {
  Uint8List? _bytes;
  String? _session;
  String? _message;
  bool _busy = false;
  bool _finished = false;

  Future<void> _prepare() async {
    if (_busy) return;
    final session = widget.token();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes = await widget.api.exportAccount(session);
      if (!mounted) return;
      if (session != widget.token()) {
        throw const ExportException(
          'حساب تغییر کرده است. این پنجره را ببندید.',
        );
      }
      setState(() {
        _bytes = bytes;
        _session = session;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is ExportException
              ? error.message
              : 'دریافت خروجی انجام نشد. دوباره امتحان کنید.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _bytes == null) return;
    if (_session != widget.token()) {
      setState(() {
        _bytes = null;
        _message = 'حساب تغییر کرده است. این پنجره را ببندید.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await widget.saver(_bytes!);
      if (!mounted) return;
      setState(() {
        _finished = result != ExportSaveResult.cancelled;
        _message = switch (result) {
          ExportSaveResult.saved => 'فایل ذخیره شد.',
          ExportSaveResult.downloadStarted =>
            'دریافت فایل به مرورگر سپرده شد. پوشهٔ دانلودها را بررسی کنید.',
          ExportSaveResult.cancelled =>
            'ذخیره لغو شد. می‌توانید دوباره انتخاب کنید.',
        };
        if (_finished) _bytes = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'ذخیره انجام نشد. دوباره امتحان کنید.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('خروجی داده‌های من'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'یک فایل JSON از کارها، پروژه‌ها، زمان‌ها و تاریخچهٔ اسپرینت دریافت کنید. فایل شامل اطلاعات شخصی شماست؛ آن را در جای امن نگه دارید.',
        ),
        const SizedBox(height: 12),
        const Text(
          'این فایل برای انتقال داده است؛ بازیابی خودکار آن هنوز در دسترس نیست.',
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(
            semanticsLabel: 'در حال آماده‌سازی خروجی',
          ),
        ],
        if (_bytes != null && !_busy) ...[
          const SizedBox(height: 12),
          const Text('فایل آماده است. محل ذخیره را انتخاب کنید.'),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(_message!)),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('بستن'),
      ),
      if (!_finished)
        FilledButton.icon(
          onPressed: _busy ? null : (_bytes == null ? _prepare : _save),
          icon: const Icon(Icons.download_outlined),
          label: Text(_bytes == null ? 'آماده‌سازی خروجی' : 'ذخیرهٔ فایل'),
        ),
    ],
  );
}
