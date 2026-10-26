import 'package:flutter/material.dart';
import 'package:mvi_dart/mvi_dart.dart';

import '../features/todos/todos_page.dart';
import 'app_feature.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => RootStore<AppState, AppAction, AppFeature>(
    initial: const AppState(),
    create: AppFeature.new,
    builder: (context, app) => const MaterialApp(title: 'Todos', home: TodosPage()),
  );
}
