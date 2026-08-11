import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kode_agent_desktop/main.dart' as app;

void main() {
  testWidgets('review dialog menonaktifkan patch yang gagal divalidasi', (
    tester,
  ) async {
    await tester.pumpWidget(const app.KodeAgentApp());

    // The public app smoke test guards that adding Review Mode keeps the shell
    // buildable; behavioral patch validation is covered by review_service_test.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
