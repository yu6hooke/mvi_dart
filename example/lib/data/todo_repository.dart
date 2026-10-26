import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'todo.dart';

abstract interface class TodoRepository {
  Future<List<Todo>> search(String query);
  Future<void> setDone(String id, bool done);
}

final class InMemoryTodoRepository implements TodoRepository {
  final Map<String, Todo> _todos = {
    for (final t in const [
      Todo(id: '1', title: 'Buy milk', done: true),
      Todo(id: '2', title: 'Write the README'),
      Todo(id: '3', title: 'Review the pull request'),
      Todo(id: '4', title: 'Book a dentist appointment', done: true),
      Todo(id: '5', title: 'Read the release notes'),
    ])
      t.id: t,
  };

  @override
  Future<List<Todo>> search(String query) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final q = query.toLowerCase();
    return _todos.values.where((t) => t.title.toLowerCase().contains(q)).toList();
  }

  @override
  Future<void> setDone(String id, bool done) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _todos[id] = _todos[id]!.copyWith(done: done);
  }
}

final todoRepositoryProvider = Provider<TodoRepository>((ref) => InMemoryTodoRepository());
