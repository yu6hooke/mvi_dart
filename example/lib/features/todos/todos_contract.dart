import 'package:freezed_annotation/freezed_annotation.dart';

import '../../data/todo.dart';

part 'todos_contract.freezed.dart';

@freezed
abstract class TodosState with _$TodosState {
  const TodosState._();
  const factory TodosState({
    @Default('') String query,
    @Default(<Todo>[]) List<Todo> todos,
    @Default(false) bool loading,
    @Default(<String>{}) Set<String> saving,
  }) = _TodosState;

  int get remaining => todos.where((t) => !t.done).length;
}

@freezed
sealed class TodosAction with _$TodosAction {
  const factory TodosAction.started() = Started;
  const factory TodosAction.queryChanged(String query) = QueryChanged;
  const factory TodosAction.loaded(List<Todo> todos) = Loaded;
  const factory TodosAction.loadFailed(String message) = LoadFailed;
  const factory TodosAction.toggled(String id) = Toggled;
  const factory TodosAction.saved(String id) = Saved;
  const factory TodosAction.saveFailed(String id, bool previous, String message) = SaveFailed;
  const factory TodosAction.opened(String id) = Opened;
}

@freezed
sealed class TodosEffect with _$TodosEffect {
  const factory TodosEffect.showError(String message) = ShowError;
  const factory TodosEffect.openDetail(Todo todo) = OpenDetail;
}
