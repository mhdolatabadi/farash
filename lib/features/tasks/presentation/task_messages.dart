import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';

/// Explains a failed task action in Persian.
String taskErrorMessage(Object error) {
  if (error is! ApiException) return 'اتصال به سرور برقرار نشد.';
  return switch (error.code) {
    'task_not_found' => 'این کار دیگر وجود ندارد.',
    'project_not_found' =>
      'پروژهٔ مقصد پیدا نشد یا کار نمی‌پذیرد (پوشه یا بایگانی‌شده).',
    'invalid_task' => 'عنوان کار باید ۱ تا ۵۰۰ نویسه باشد.',
    'parent_not_found' => 'کار بالادستی دیگر وجود ندارد.',
    'invalid_parent' =>
      'این کار آن‌جا جا نمی‌گیرد: زیرکارها تا پنج سطح، در همان پروژه و زیر کاری باز.',
    'invalid_task_order' => 'ترتیب کارها ذخیره نشد. فهرست را تازه کنید.',
    _ => error.message,
  };
}

void showTaskError(BuildContext context, Object error) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(taskErrorMessage(error))));
}
