import 'package:flutter_test/flutter_test.dart';
import 'package:mvi_dart_example/features/todos/todos_contract.dart';
import 'package:mvi_dart_example/features/todos/todos_feature.dart';
import 'package:mvi_dart_example/shared/remaining_count.dart';
import 'package:mvi_dart_test/mvi_dart_test.dart';

import 'fake_repo.dart';

FeatureTester<TodosState, TodosAction, TodosEffect, TodosFeature> tester(
  FakeAsync fa,
  FakeTodoRepository repo, {
  TodosState initial = const TodosState(),
}) => FeatureTester(fa, initial, (ctx) => TodosFeature(ctx, repo: repo), trackShared: [remainingCount]);

void main() {
  test(
    'loads on start and publishes the remaining count',
    () => fakeAsync((fa) {
      final h = tester(fa, FakeTodoRepository());
      h.send(const TodosAction.started(), (s) => s.copyWith(loading: true));
      h.advance(const Duration(milliseconds: 100));
      h.receive(TodosAction.loaded(sampleTodos), (s) => s.copyWith(todos: sampleTodos, loading: false));
      h.expectShared(remainingCount, 0, 2);
    }),
  );

  test(
    'search waits 300ms and cancels the search for earlier input',
    () => fakeAsync((fa) {
      final repo = FakeTodoRepository();
      final h = tester(fa, repo);
      h.send(const TodosAction.queryChanged('Write'), (s) => s.copyWith(query: 'Write', loading: true));
      h.advance(const Duration(milliseconds: 200));
      h.send(const TodosAction.queryChanged('Write t'), (s) => s.copyWith(query: 'Write t'));
      h.advance(const Duration(milliseconds: 399));
      expect(h.unasserted, isEmpty);
      h.advance(const Duration(milliseconds: 1));
      h.receive(TodosAction.loaded([sampleTodos[2]]), (s) => s.copyWith(todos: [sampleTodos[2]], loading: false));
      h.expectShared(remainingCount, 0, 1);
      expect(repo.searches, ['Write t']);
    }),
  );

  test(
    'a toggle shows immediately, ignores repeats while saving, and reverts with an error on failure',
    () => fakeAsync((fa) {
      final repo = FakeTodoRepository()..failNextSave = true;
      final h = tester(fa, repo, initial: const TodosState(todos: sampleTodos));
      h.send(
        const TodosAction.toggled('2'),
        (s) => s.copyWith(todos: [sampleTodos[0], sampleTodos[1].copyWith(done: true), sampleTodos[2]], saving: {'2'}),
      );
      h.expectShared(remainingCount, 0, 1);
      h.send(const TodosAction.toggled('2'));
      h.advance(const Duration(milliseconds: 300));
      h.receive(
        const TodosAction.saveFailed('2', false, 'Could not save'),
        (s) => s.copyWith(todos: sampleTodos, saving: {}),
      );
      h.expectShared(remainingCount, 1, 2);
      h.expectEffect(const TodosEffect.showError('Could not save'));
    }),
  );
}
