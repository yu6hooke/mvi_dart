import 'package:mvi_dart_example/data/todo.dart';
import 'package:mvi_dart_example/data/todo_repository.dart';

const sampleTodos = [
  Todo(id: '1', title: 'Buy milk', done: true),
  Todo(id: '2', title: 'Write docs'),
  Todo(id: '3', title: 'Write tests'),
];

/// Keeps real delays so debounce and cancellation are exercised with real (fake-clock) time.
final class FakeTodoRepository implements TodoRepository {
  final List<String> searches = [];
  bool failNextSave = false;

  @override
  Future<List<Todo>> search(String query) async {
    searches.add(query);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return sampleTodos.where((t) => t.title.contains(query)).toList();
  }

  @override
  Future<void> setDone(String id, bool done) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (failNextSave) {
      failNextSave = false;
      throw Exception('network');
    }
  }
}
