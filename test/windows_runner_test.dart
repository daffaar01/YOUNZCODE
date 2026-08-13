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

    expect(header, contains('clipboard_sequence_on_deactivate_'));
    expect(header, contains('clipboard_change_watch_active_'));
    expect(header, contains('clipboard_poll_attempts_'));
    expect(source, contains('GetClipboardSequenceNumber()'));
    expect(source, contains('inactive_duration <= 30000'));
    expect(source, contains('SetTimer(hwnd, kClipboardHistoryPollTimer, 50'));
    expect(source, contains('clipboard_poll_attempts_ >= 20'));
    expect(source, contains('case WM_TIMER:'));
    expect(source, contains('SendInput(4, inputs, sizeof(INPUT))'));
  });
}
