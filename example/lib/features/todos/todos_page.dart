import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:mvi_dart/mvi_dart.dart';

import '../../app/app_feature.dart';
import '../../di.dart';
import '../../hooks.dart';
import '../../shared/remaining_badge.dart';
import '../detail/detail_page.dart';
import 'todos_contract.dart';
import 'todos_feature.dart';
import 'todos_providers.dart';

class TodosPage extends StatelessWidget {
  const TodosPage({super.key});

  @override
  Widget build(BuildContext context) => context.feature<AppFeature>().scope(
    lens: todosLens,
    wrapAction: AppAction.todos,
    create: context.read(todosFeatureProvider),
    builder: (context, todos) => TodosView(todos),
  );
}

class TodosView extends HookWidget {
  const TodosView(this.todos, {super.key});
  final TodosFeature todos;

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      todos.send(const TodosAction.started());
      return null;
    }, [todos]);

    useEffects(todos, (effect) {
      switch (effect) {
        case ShowError(:final message):
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        case OpenDetail(:final todo):
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DetailPage(todo: todo)));
      }
    });

    final loading = useSelect(todos.state, (s) => s.loading);

    return Scaffold(
      appBar: AppBar(title: const Text('Todos'), actions: const [RemainingBadge()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const Key('search'),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
              onChanged: (q) => todos.send(TodosAction.queryChanged(q)),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Expanded(child: _TodoList(todos)),
        ],
      ),
    );
  }
}

class _TodoList extends HookWidget {
  const _TodoList(this.todos);
  final TodosFeature todos;

  @override
  Widget build(BuildContext context) {
    final list = useSelect(todos.state, (s) => s.todos);
    final saving = useSelect(todos.state, (s) => s.saving);
    return ListView(
      children: [
        for (final t in list)
          ListTile(
            key: Key('todo-${t.id}'),
            title: Text(t.title),
            onTap: () => todos.send(TodosAction.opened(t.id)),
            trailing: saving.contains(t.id)
                ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Checkbox(
                    key: Key('done-${t.id}'),
                    value: t.done,
                    onChanged: (_) => todos.send(TodosAction.toggled(t.id)),
                  ),
          ),
      ],
    );
  }
}
