import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';

/// Explains a failed project action in Persian.
String projectErrorMessage(Object error) {
  if (error is! ApiException) return 'اتصال به سرور برقرار نشد.';
  return switch (error.code) {
    'inbox_project' =>
      'صندوق ورودی را نمی‌شود تغییر نام داد، جابه‌جا، بایگانی یا حذف کرد.',
    'invalid_project_name' => 'نام پروژه را بنویسید.',
    'project_create_failed' =>
      'پروژه ساخته نشد؛ شاید پروژهٔ بالادستی دیگر وجود ندارد.',
    'project_not_found' => 'این پروژه دیگر وجود ندارد.',
    _ => error.message,
  };
}

void showProjectError(BuildContext context, Object error) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(projectErrorMessage(error))));
}
