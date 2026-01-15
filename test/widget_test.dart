import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:discord_cloud/main.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const DiscordCloudApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
