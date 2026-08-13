import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runner tidak merebut fokus saat Windows menonaktifkan aplikasi', () {
    final source = File('windows/runner/win32_window.cpp').readAsStringSync();

    expect(source, contains('LOWORD(wparam) != WA_INACTIVE'));
    expect(
      source,
      isNot(contains('case WM_ACTIVATE:\n      if (child_content_')),
    );
  });
}
