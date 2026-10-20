import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:op_list/data/models/todo_item.dart';
import 'package:op_list/ui/widgets/item_tile.dart';

void main() {
  testWidgets('ItemTile renders summary, badges, and interaction buttons', (WidgetTester tester) async {
    final now = DateTime.now();
    final item = TodoItem(
      id: 'test_1',
      haEntityId: 'todo.test',
      summary: 'Almond Milk',
      description: 'Unsweetened',
      category: 'dairy',
      isPerishable: true,
      humanOrderIndex: 0,
      optimizedOrderIndex: 2,
      isPinned: true,
      createdAt: now,
      updatedAt: now,
    );

    var toggledComplete = false;
    var toggledPin = false;
    var edited = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemTile(
            item: item,
            index: 0,
            onToggleComplete: () => toggledComplete = true,
            onTogglePin: () => toggledPin = true,
            onDelete: () {},
            onEdit: () => edited = true,
          ),
        ),
      ),
    );

    // Verify UI contents
    expect(find.text('Almond Milk'), findsOneWidget);
    expect(find.text('Unsweetened'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Stop #2'), findsOneWidget);
    expect(find.text('Keep cold'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    // Tap checkbox
    await tester.tap(find.byType(Checkbox));
    expect(toggledComplete, isTrue);

    // Tap pin
    await tester.tap(find.byIcon(Icons.push_pin));
    expect(toggledPin, isTrue);

    // Tapping the card body opens the editor
    await tester.tap(find.text('Almond Milk'));
    expect(edited, isTrue);
  });
}
