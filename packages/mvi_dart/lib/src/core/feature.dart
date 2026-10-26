import 'dart:async';

import 'package:flutter/foundation.dart';

import 'effect.dart';
import 'shared.dart';
import 'store.dart';
import 'task.dart';

final class FeatureContext<S, A> {
  FeatureContext({required this.cell, required this.upstream, required this.shared, this.onTaskAction});

  factory FeatureContext.detached(
    StateCell<S> cell, {
    void Function(A action)? upstream,
    SharedStore? shared,
    void Function(A action)? onTaskAction,
  }) => FeatureContext(
    cell: cell,
    upstream: upstream ?? (_) {},
    shared: shared ?? SharedStore(),
    onTaskAction: onTaskAction,
  );

  final StateCell<S> cell;
  final void Function(A action) upstream;
  final SharedStore shared;

  final void Function(A action)? onTaskAction;
}

abstract base class Feature<S, A, E> {
  Feature(FeatureContext<S, A> ctx)
    : cell = ctx.cell,
      _upstream = ctx.upstream,
      _onTaskAction = ctx.onTaskAction,
      shared = ctx.shared;

  final StateCell<S> cell;
  final void Function(A) _upstream;
  final void Function(A)? _onTaskAction;
  final SharedStore shared;
  final EffectChannel<E> effects = EffectChannel<E>();
  late final TaskRunner<A> _tasks = TaskRunner<A>(_fromTask);
  final List<void Function()> _disposers = [];
  bool _mounted = true;

  ValueListenable<S> get state => cell;

  bool get hasRunningTasks => !_tasks.isIdle;

  @protected
  @nonVirtual
  S get uiState => cell.value;

  @protected
  @nonVirtual
  set uiState(S next) {
    if (_mounted) cell.set(next);
  }

  /// No custom queue: microtasks already run FIFO and one at a time, which makes ordering,
  /// re-entrant sends from a reducer, and sends during build safe without extra machinery.
  @nonVirtual
  void send(A action) => scheduleMicrotask(() => _process(action));

  void _process(A action) {
    if (!_mounted) return;
    final before = cell.value;
    try {
      onReceive(action);
    } catch (_) {
      // Do not keep a half-written State, and do not forward the failed action to the parent.
      if (_mounted) cell.set(before);
      rethrow;
    }
    if (_mounted) _upstream(action);
  }

  void _fromTask(A action) {
    _onTaskAction?.call(action);
    send(action);
  }

  /// Must be synchronous. An await here breaks the ordering guarantee; put waiting work in [run].
  @visibleForOverriding
  void onReceive(A action);

  @protected
  @nonVirtual
  void emit(E effect) {
    if (_mounted) effects.emit(effect);
  }

  /// A running task with the same [id] is cancelled first (latest wins).
  /// "Drop while running" is not built in: the reducer can check State and skip [run].
  @protected
  @nonVirtual
  void run(Task<A> task, {Object? id}) {
    if (_mounted) _tasks.run(task, id: id);
  }

  @protected
  @nonVirtual
  void cancel(Object id) => _tasks.cancel(id);

  @protected
  @nonVirtual
  void combineWith<T>(ValueListenable<T> source, S Function(S state, T value) merge) {
    void listener() => uiState = merge(uiState, source.value);
    source.addListener(listener);
    _disposers.add(() => source.removeListener(listener));
    listener();
  }

  @protected
  void onDispose(void Function() cb) => _disposers.add(cb);

  @mustCallSuper
  void dispose() {
    if (!_mounted) return;
    _mounted = false;
    _tasks.dispose();
    for (final d in _disposers.reversed) {
      d();
    }
    effects.dispose();
  }
}
