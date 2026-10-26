import 'package:mvi_dart/mvi_dart.dart';

import '../../data/todo.dart';
import '../../data/todo_repository.dart';
import '../../shared/remaining_count.dart';
import 'todos_contract.dart';

final class TodosFeature extends Feature<TodosState, TodosAction, TodosEffect> {
  TodosFeature(super.ctx, {required this.repo}) : _remaining = ctx.shared(remainingCount);

  final TodoRepository repo;
  final Shared<int> _remaining;

  static const debounce = Duration(milliseconds: 300);

  @override
  void onReceive(TodosAction action) {
    switch (action) {
      case Started():
        _load(uiState.query);

      case QueryChanged(:final query):
        uiState = uiState.copyWith(query: query);
        _load(query, wait: debounce);

      case Loaded(:final todos):
        _setTodos(todos);
        uiState = uiState.copyWith(loading: false);

      case LoadFailed(:final message):
        uiState = uiState.copyWith(loading: false);
        emit(TodosEffect.showError(message));

      case Toggled(:final id) when uiState.saving.contains(id):
        return;

      case Toggled(:final id):
        final done = !uiState.todos.firstWhere((t) => t.id == id).done;
        _setDone(id, done); // optimistic: show it now, revert on failure
        uiState = uiState.copyWith(saving: {...uiState.saving, id});
        run(id: ('save', id), (life) async* {
          try {
            await life.guard(repo.setDone(id, done));
            yield TodosAction.saved(id);
          } on Cancelled {
            rethrow;
          } catch (_) {
            yield TodosAction.saveFailed(id, !done, 'Could not save');
          }
        });

      case Saved(:final id):
        uiState = uiState.copyWith(saving: {...uiState.saving}..remove(id));

      case SaveFailed(:final id, :final previous, :final message):
        _setDone(id, previous);
        uiState = uiState.copyWith(saving: {...uiState.saving}..remove(id));
        emit(TodosEffect.showError(message));

      case Opened(:final id):
        emit(TodosEffect.openDetail(uiState.todos.firstWhere((t) => t.id == id)));
    }
  }

  void _load(String query, {Duration wait = Duration.zero}) {
    uiState = uiState.copyWith(loading: true);
    run(id: #load, (life) async* {
      try {
        if (wait > Duration.zero) await life.delay(wait);
        yield TodosAction.loaded(await life.guard(repo.search(query)));
      } on Cancelled {
        rethrow;
      } catch (_) {
        yield const TodosAction.loadFailed('Could not load');
      }
    });
  }

  void _setDone(String id, bool done) =>
      _setTodos([for (final t in uiState.todos) t.id == id ? t.copyWith(done: done) : t]);

  void _setTodos(List<Todo> todos) {
    uiState = uiState.copyWith(todos: todos);
    _remaining.value = uiState.remaining;
  }
}
