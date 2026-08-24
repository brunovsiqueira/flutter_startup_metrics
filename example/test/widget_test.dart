import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_startup_metrics_example/main.dart';

void main() {
  testWidgets('shows a spinner until the report resolves', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
