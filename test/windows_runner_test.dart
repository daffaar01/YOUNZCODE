import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runner tidak merebut fokus saat Windows menonaktifkan aplikasi', () {
    final source = File('windows/runner/win32_window.cpp').readAsStringSync();

    expect(source, contains('LOWORD(wparam) == WA_INACTIVE'));
    expect(source, contains('} else if (child_content_ != nullptr)'));
    expect(
      source,
      isNot(contains('case WM_ACTIVATE:\n      if (child_content_')),
    );
  });

  test('runner meneruskan pilihan Clipboard History setelah fokus pulih', () {
    final source = File('windows/runner/win32_window.cpp').readAsStringSync();
    final header = File('windows/runner/win32_window.h').readAsStringSync();

    expect(header, contains('clipboard_history_pending_'));
    expect(source, contains("wparam == 'V'"));
    expect(source, contains("GetAsyncKeyState('V')"));
    expect(source, contains('SetTimer(hwnd, kPasteClipboardHistoryTimer, 120'));
    expect(source, contains('case WM_TIMER:'));
    expect(source, contains('SendInput(4, inputs, sizeof(INPUT))'));
  });
}
