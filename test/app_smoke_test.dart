import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/data/database/app_database.dart';
import 'package:op_list/main.dart';

void main() {
  testWidgets('app boots with sample data and every tab renders', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => AppDatabase.instance.init(inMemory: true));

    await tester.pumpWidget(const OpListApp());
    // SQLite runs on a background isolate: let real async work finish.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    expect(find.text('Passport Application Attestation'), findsOneWidget);
    expect(find.text('Local only'), findsOneWidget);
    expect(find.text("I'm Going Out"), findsOneWidget);

    for (final tab in ['Radar Map', 'Stores & DAG', 'Settings', 'Errands']) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull, reason: 'tab $tab threw');
    }

    // Add-item sheet guesses the category from the title.
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Vanilla ice cream');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(DropdownButton<String>),
        matching: find.text('Frozen Foods'),
      ),
      findsOneWidget,
    );

    await tester.runAsync(() => AppDatabase.instance.close());
  });
}
