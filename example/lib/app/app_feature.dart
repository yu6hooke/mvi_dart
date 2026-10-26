import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:mvi_dart/mvi_dart.dart';

import '../features/todos/todos_contract.dart';

part 'app_feature.freezed.dart';

@freezed
abstract class AppState with _$AppState {
  const factory AppState({@Default(TodosState()) TodosState todos}) = _AppState;
}

@freezed
sealed class AppAction with _$AppAction {
  const factory AppAction.todos(TodosAction action) = AppTodos;
}

final todosLens = Lens<AppState, TodosState>(
  get: (s) => s.todos,
  set: (s, t) => s.copyWith(todos: t),
);

final class AppFeature extends Feature<AppState, AppAction, Never> {
  AppFeature(super.ctx);

  @override
  void onReceive(AppAction action) {
    switch (action) {
      case AppTodos():
        break; // the child reducer already applied it
    }
  }
}
