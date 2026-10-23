import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/features/labels/application/labels_controller.dart';
import 'package:farash/features/labels/data/label.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/recurrence/task_recurrence.dart';
import 'package:farash/features/tasks/data/quick_parse.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';

/// One capture intent. A confirmed task survives a failed recurrence write;
/// retry completes only its rule, never creates another confirmed task.
class QuickCaptureSession {
  QuickCaptureSession({
    required this.api,
    required this.token,
    required this.projects,
    required this.defaultProject,
    this.sections,
    this.labels,
  });

  final TasksApi api;
  final SectionsApi? sections;
  final LabelsController? labels;
  final String? Function() token;
  final List<Project> Function() projects;
  final Project Function() defaultProject;
  Task? _created;
  String? _fingerprint, _session;
  Map<String, Object?>? _schedule;
  bool get hasPendingRecurrence => _created != null;

  Future<Task> capture(
    QuickTask parsed,
    String raw, {
    required String calendar,
    TaskPriority menuPriority = TaskPriority.p4,
    DateTime? now,
  }) async {
    final current = token();
    if (current == null) {
      throw const ApiException('نشست شما منقضی شده است. دوباره وارد شوید.');
    }
    final fingerprint =
        '$raw\u0000${menuPriority.level}\u0000$calendar\u0000${defaultProject().id}';
    if (_created != null &&
        (fingerprint != _fingerprint || current != _session)) {
      throw const ApiException(
        'کار قبلی ساخته شد اما تکرارش ذخیره نشد؛ همان متن را دوباره بفرستید یا تکرار را در جزئیات آن کار تنظیم کنید.',
      );
    }
    if (_created == null) {
      var target = defaultProject();
      var title = parsed.title;
      if (parsed.project case final name?) {
        final matches = projects()
            .where(
              (p) =>
                  !p.isFolder &&
                  !p.isArchived &&
                  p.displayName.toLowerCase() == name.toLowerCase(),
            )
            .toList();
        if (matches.length > 1) {
          throw const ApiException(
            'نام پروژه تکراری است. پروژه را از فهرست باز کنید.',
          );
        }
        if (matches.isEmpty) {
          throw const ApiException(
            'پروژه پیدا نشد. نام پروژه را بررسی کنید یا نشانهٔ پروژه را نادیده بگیرید.',
          );
        } else {
          target = matches.single;
        }
      }
      String? sectionId;
      if (parsed.section case final name?) {
        final service = sections;
        if (service == null) {
          throw const ApiException('بخش‌ها در این اتصال در دسترس نیستند.');
        }
        final choices = (await service.listSections(
          current,
          target.id,
        )).where((s) => s.name.toLowerCase() == name.toLowerCase()).toList();
        if (choices.length != 1) {
          throw const ApiException(
            'بخش پیدا نشد یا نامش تکراری است. نام بخش و پروژه را بررسی کنید.',
          );
        }
        sectionId = choices.single.id;
      }
      final recurring = parsed.recurrence;
      if (recurring != null && api is! TimeApi) {
        throw const ApiException('ذخیرهٔ تکرار در این اتصال در دسترس نیست.');
      }
      var day = parsed.day;
      if (recurring != null) {
        if (parsed.tokens.any((t) => t.kind == QuickTokenKind.date)) {
          if (!recurring.accepts(day!, calendar)) {
            throw const ApiException('تاریخ آغاز با روز تکرار سازگار نیست.');
          }
        } else {
          day = recurring.firstDay(day ?? now ?? DateTime.now(), calendar);
        }
      }
      // Only timed or recurring captures need the zone; asking the platform
      // for an all-day task would stall where no plugin answers.
      final zone = day != null && (parsed.hour != null || recurring != null)
          ? await deviceTimeZone()
          : null;
      final due = day == null
          ? null
          : parsed.hour == null
          ? TaskDue.onDay(day)
          : TaskDue.at(
              DateTime(
                day.year,
                day.month,
                day.day,
                parsed.hour!,
                parsed.minute,
              ),
              zone!,
            );
      if (recurring != null) {
        _schedule = recurring.schedule(
          start: due!.date,
          timezone: zone!,
          calendar: calendar,
          wallTime: parsed.hour == null
              ? null
              : '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}',
        );
      }
      final labelIds = <String>[];
      for (final name in parsed.labels) {
        final service = labels;
        if (service == null) {
          title = '$title @$name'.trim();
          continue;
        }
        final matches = service.labels
            .where((l) => l.name.toLowerCase() == name.toLowerCase())
            .toList();
        if (matches.length > 1) {
          throw const ApiException(
            'نام برچسب تکراری است. برچسب را از جزئیات انتخاب کنید.',
          );
        }
        labelIds.add(
          matches.isEmpty
              ? (await service.create(LabelDraft(name: name))).id
              : matches.single.id,
        );
      }
      if (title.isEmpty) title = raw.trim();
      if (token() != current) {
        throw const ApiException('حساب تغییر کرده است؛ افزودن انجام نشد.');
      }
      final task = await api.createTask(
        current,
        TaskDraft(
          projectId: target.id,
          sectionId: sectionId,
          title: title,
          priority: parsed.priority == null
              ? menuPriority
              : TaskPriority.fromLevel(parsed.priority!),
          dates: TaskDates(
            due: due,
            deadline: parsed.deadline == null
                ? null
                : dateKey(parsed.deadline!),
          ),
          labelIds: labelIds.isEmpty ? null : labelIds,
        ),
      );
      if (recurring == null) return task;
      _created = task;
      _session = current;
      _fingerprint = fingerprint;
    }
    if (token() != current) {
      throw const ApiException(
        'حساب تغییر کرده است. تکرار هنوز ذخیره نشده است.',
      );
    }
    try {
      final state = await RecurrenceService(
        api as TimeApi,
        token,
      ).save(_created!.id, _schedule);
      if (state == null) throw StateError('Missing confirmed recurrence');
    } catch (_) {
      throw const ApiException(
        'کار ساخته شد اما تکرارش ذخیره نشد. همان متن را دوباره بفرستید تا فقط تکرار دوباره ذخیره شود.',
      );
    }
    final task = _created!;
    _created = null;
    _session = null;
    _fingerprint = null;
    _schedule = null;
    return task;
  }
}
