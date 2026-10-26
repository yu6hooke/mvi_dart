import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvi_dart_example/app/app.dart';
import 'package:mvi_dart_example/data/todo_repository.dart';

import 'fake_repo.dart';

Future<FakeTodoRepository> launch(WidgetTester t) async {
  final repo = FakeTodoRepository();
  await t.pumpWidget(ProviderScope(overrides: [todoRepositoryProvider.overrideWithValue(repo)], child: const App()));
  await t.pump(const Duration(milliseconds: 100));
  return repo;
}

void main() {
  testWidgets('shows the list and the remaining count on start', (t) async {
    await launch(t);
    expect(find.text('Write docs'), findsOneWidget);
    expect(find.text('2 left'), findsOneWidget);
  });

  testWidgets('a toggle shows on the next frame (optimistic update)', (t) async {
    await launch(t);
    await t.tap(find.byKey(const Key('done-2')));
    await t.pump();
    expect(find.text('1 left'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.pump(const Duration(milliseconds: 300));
    expect(t.widget<Checkbox>(find.byKey(const Key('done-2'))).value, isTrue);
  });

  testWidgets('typing searches after 300ms', (t) async {
    final repo = await launch(t);
    await t.enterText(find.byKey(const Key('search')), 'tests');
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Write tests'), findsOneWidget);
    expect(find.text('Write docs'), findsNothing);
    expect(repo.searches.last, 'tests');
  });

  testWidgets('a failed save reverts and shows a SnackBar', (t) async {
    final repo = await launch(t);
    repo.failNextSave = true;
    await t.tap(find.byKey(const Key('done-2')));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(find.text('Could not save'), findsOneWidget);
    expect(find.text('2 left'), findsOneWidget);
  });

  testWidgets('tapping an item opens the detail route, which sees the same shared value', (t) async {
    await launch(t);
    await t.tap(find.byKey(const Key('todo-2')));
    await t.pumpAndSettle();
    expect(find.text('Todos'), findsNothing);
    expect(find.byKey(const Key('status')), findsOneWidget);
    expect(find.text('2 left'), findsOneWidget);
  });
}
