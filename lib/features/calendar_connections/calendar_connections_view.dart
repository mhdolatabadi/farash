import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';

import 'calendar_browser.dart';
import 'calendar_connections.dart';

typedef CalendarBrowser = Future<void> Function(Uri uri);

class CalendarConnectionsView extends StatefulWidget {
  const CalendarConnectionsView({
    super.key,
    required this.api,
    required this.token,
    this.openBrowser = openCalendarAuthorization,
  });
  final CalendarConnectionsApi api;
  final String? Function() token;
  final CalendarBrowser openBrowser;

  @override
  State<CalendarConnectionsView> createState() =>
      _CalendarConnectionsViewState();
}

class _CalendarConnectionsViewState extends State<CalendarConnectionsView>
    with WidgetsBindingObserver {
  late final CalendarConnectionsController controller =
      CalendarConnectionsController(api: widget.api, token: widget.token);
  bool _waitingForBrowser = false;
  final _completionCode = TextEditingController();
  late final String? _codeSession = widget.token();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_clearExpiredCode);
    _completionCode.addListener(_codeChanged);
    controller.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForBrowser) {
      _waitingForBrowser = false;
      controller.load();
    }
  }

  void _codeChanged() {
    if (mounted) setState(() {});
  }

  void _clearExpiredCode() {
    if (controller.error != null || widget.token() != _codeSession) {
      _completionCode.clear();
    }
  }

  Future<void> _completeAuthorization() async {
    if (widget.token() != _codeSession) {
      _completionCode.clear();
      await controller.load();
      return;
    }
    final code = _completionCode.text;
    _completionCode.clear();
    _waitingForBrowser = false;
    await controller.completeAuthorization(code);
  }

  Future<void> _openBrowser() async {
    final uri = controller.takeAuthorization();
    if (uri == null) return;
    _waitingForBrowser = true;
    try {
      await widget.openBrowser(uri);
    } catch (_) {
      _waitingForBrowser = false;
      controller.browserFailed();
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('قطع اتصال Google؟'),
        content: const Text(
          'رویدادها از Google حذف نمی‌شوند. نمایش آن‌ها در فراش متوقف می‌شود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('قطع اتصال'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await controller.disconnect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_clearExpiredCode);
    controller.dispose();
    _completionCode.removeListener(_codeChanged);
    _completionCode.clear();
    _completionCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      final settings = CalendarScope.of(context);
      final connection = controller.connection;
      final busy = controller.busy;
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(context).scale(kToolbarHeight),
          title: const Text(
            'اتصال تقویم‌ها',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'بررسی وضعیت اتصال',
              onPressed: busy ? null : controller.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'Google Calendar',
                    textAlign: TextAlign.start,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'نمایش رویدادهای Google؛ بدون تغییر در تقویم یا کارها.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(
                      semanticsLabel: 'دریافت اطلاعات تقویم',
                    ),
                  ],
                  if (controller.error case final message?) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: busy ? null : controller.load,
                        child: const Text('بازخوانی اطلاعات'),
                      ),
                    ),
                  ],
                  if (controller.notice case final message?) ...[
                    const SizedBox(height: 16),
                    Semantics(liveRegion: true, child: Text(message)),
                  ],
                  const SizedBox(height: 20),
                  if (controller.loaded && !controller.configured)
                    const Text(
                      'اتصال Google هنوز روی این سرور فعال نشده است. مدیر سرور باید تنظیمات اتصال را تکمیل کند.',
                    ),
                  if (controller.configured &&
                      (connection == null || connection.needsReconnect)) ...[
                    Text(
                      connection == null
                          ? 'حساب Google متصل نیست.'
                          : 'دسترسی Google نیاز به تأیید دوباره دارد.',
                    ),
                    const SizedBox(height: 12),
                    if (controller.authorization == null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => controller.prepareAuthorization(
                                  kIsWeb ? 'web' : 'android',
                                ),
                          icon: const Icon(Icons.link),
                          label: Text(
                            connection == null
                                ? 'آماده‌سازی اتصال Google'
                                : 'آماده‌سازی اتصال دوباره',
                          ),
                        ),
                      ),
                    if (controller.authorization != null) ...[
                      const Text(
                        'اتصال آماده است. برای انتخاب حساب و تأیید دسترسی، Google را در مرورگر باز کنید.',
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton.icon(
                          onPressed: busy ? null : _openBrowser,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('باز کردن Google'),
                        ),
                      ),
                    ],
                  ],
                  if (controller.configured &&
                      (connection == null || connection.needsReconnect)) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'در پایان تأیید مرورگر، یک کد موقت نمایش داده می‌شود. آن را فقط در همین حساب فراش وارد کنید. کد پس از ۱۰ دقیقه منقضی می‌شود.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _completionCode,
                      enabled: !busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      maxLength: 43,
                      decoration: const InputDecoration(
                        labelText: 'کد تأیید اتصال',
                        hintText: 'کد یک‌بارمصرف مرورگر',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _completeAuthorization(),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton(
                        onPressed: busy || _completionCode.text.trim().isEmpty
                            ? null
                            : _completeAuthorization,
                        child: const Text('ثبت اتصال'),
                      ),
                    ),
                  ],
                  if (connection != null) ...[
                    if (!connection.needsReconnect) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('حساب Google متصل است.')),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'تقویم‌های قابل نمایش',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'حداکثر ۲۰ تقویم را انتخاب کنید. تغییرات پس از ذخیره اعمال می‌شوند.',
                      ),
                      if (controller.calendars.isEmpty && !busy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('تقویمی برای این حساب پیدا نشد.'),
                        ),
                      for (final calendar in controller.calendars)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(calendar.title),
                          subtitle: calendar.timeZone.isEmpty
                              ? null
                              : Text(
                                  calendar.timeZone,
                                  textDirection: TextDirection.ltr,
                                ),
                          value: controller.selection.contains(calendar.id),
                          onChanged: busy
                              ? null
                              : (value) => controller.select(
                                  calendar.id,
                                  value == true,
                                ),
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton(
                          onPressed: busy || !controller.selectionChanged
                              ? null
                              : controller.saveSelection,
                          child: const Text('ذخیرهٔ انتخاب تقویم‌ها'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text('رویدادها', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        '${formatDate(controller.from, settings)} تا ${formatDate(DateTime(controller.to.year, controller.to.month, controller.to.day - 1), settings)}',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => controller.moveWeek(-1),
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('هفتهٔ قبل'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => controller.moveWeek(1),
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('هفتهٔ بعد'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'زمان رویدادهای ساعتی بر اساس ساعت این دستگاه نمایش داده می‌شود. رویدادهای تمام‌روز تاریخ اصلی خود را حفظ می‌کنند.',
                      ),
                      if (!busy && controller.events.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            !controller.calendars.any(
                                  (calendar) => calendar.selected,
                                )
                                ? 'برای نمایش رویدادها، یک تقویم انتخاب و ذخیره کنید.'
                                : 'رویدادی در این بازه پیدا نشد.',
                          ),
                        ),
                      for (final event in controller.events) ...[
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_outlined),
                          title: Text(event.title),
                          subtitle: Text(_eventDate(context, event)),
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : _disconnect,
                        icon: const Icon(Icons.link_off),
                        label: const Text('قطع اتصال Google'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  String _eventDate(BuildContext context, ConnectedEvent event) {
    final settings = CalendarScope.of(context);
    final start = event.startsAt;
    final end = event.endsAt;
    final endDay = event.allDay
        ? DateTime(end.year, end.month, end.day - 1)
        : end;
    final date = formatDate(start, settings, withWeekday: true);
    if (event.allDay) {
      return dayOf(start) == dayOf(endDay)
          ? '$date · تمام‌روز'
          : '$date تا ${formatDate(endDay, settings)} · تمام‌روز';
    }
    return '$date · ${formatTime(start)} تا ${formatDate(end, settings)} ${formatTime(end)}';
  }
}
