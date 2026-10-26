import 'package:flutter/material.dart';

import '../../data/todo.dart';
import '../../shared/remaining_badge.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.todo});
  final Todo todo;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(todo.title), actions: const [RemainingBadge()]),
    body: Center(child: Text(todo.done ? 'Done' : 'Open', key: const Key('status'))),
  );
}
