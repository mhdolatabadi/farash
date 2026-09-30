import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';

/// Explains a failed project action in Persian.
String projectErrorMessage(Object error) {
  if (error is! ApiException) return 'اتصال به سرور برقرار نشد.';
  return switch (error.code) {
    'invalid_parent' =>
      'این پروژه را نمی‌شود آنجا گذاشت: یا بیش از چهار سطح تو در تو می‌شود '
          'یا پروژهٔ مقصد بایگانی شده است.',
    'inbox_protected' =>
      'صندوق ورودی را نمی‌شود تغییر نام داد، جابه‌جا، '
          'بایگانی یا حذف کرد.',
    'invalid_name' => 'نام پروژه باید ۱ تا ۱۲۰ نویسه و در یک خط باشد.',
    'not_found' => 'این پروژه دیگر وجود ندارد.',
    _ => error.message,
  };
}

void showProjectError(BuildContext context, Object error) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(projectErrorMessage(error))));
}
