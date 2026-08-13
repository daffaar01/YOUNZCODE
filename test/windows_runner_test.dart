import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runner tidak merebut fokus saat Windows menonaktifkan aplikasi', () {
    final source = File('windows/runner/win32_window.cpp').readAsStringSync();

    expect(source, contains('LOWORD(wparam) != WA_INACTIVE'));
    expect(source, contains('&& child_content_ != nullptr'));
    expect(
      source,
      isNot(contains('case WM_ACTIVATE:\n      if (child_content_')),
    );
  });

  test('runner tidak menyuntikkan input keyboard global', () {
    final source = File('windows/runner/win32_window.cpp').readAsStringSync();
    final header = File('windows/runner/win32_window.h').readAsStringSync();

    expect(header, isNot(contains('clipboard_sequence_on_deactivate_')));
    expect(source, isNot(contains('GetClipboardSequenceNumber()')));
    expect(source, isNot(contains('SendInput(')));
  });
}
