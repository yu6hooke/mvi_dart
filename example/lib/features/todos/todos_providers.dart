import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mvi_dart/mvi_dart.dart';

import '../../data/todo_repository.dart';
import 'todos_contract.dart';
import 'todos_feature.dart';

final todosFeatureProvider = Provider<FeatureFactory<TodosState, TodosAction, TodosFeature>>(
  (ref) =>
      (featureContext) => TodosFeature(featureContext, repo: ref.watch(todoRepositoryProvider)),
);
