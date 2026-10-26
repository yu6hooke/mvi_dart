library;

export 'package:fake_async/fake_async.dart' show FakeAsync, fakeAsync;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart' as m show addTearDown, expect, fail;

import 'package:mvi_dart/mvi_dart.dart';

sealed class Observed {
  const Observed();
}

final class StateChanged<S> extends Observed {
  const StateChanged(this.prev, this.next);
  final S prev, next;
  @override
  String toString() => 'StateChanged($prev → $next)';
}

final class SharedChanged extends Observed {
  const SharedChanged(this.key, this.prev, this.next);
  final SharedKey<Object?> key;
  final Object? prev, next;
  @override
  bool operator ==(Object other) =>
      other is SharedChanged && identical(other.key, key) && other.prev == prev && other.next == next;
  @override
  int get hashCode => Object.hash(key, prev, next);
  @override
  String toString() => 'SharedChanged(${key.debugName}: $prev → $next)';
}

final class Received<A> extends Observed {
  const Received(this.action);
  final A action;
  @override
  bool operator ==(Object other) => other is Received && other.action == action;
  @override
  int get hashCode => action.hashCode;
  @override
  String toString() => 'Received($action)';
}

final class Emitted<E> extends Observed {
  const Emitted(this.effect);
  final E effect;
  @override
  bool operator ==(Object other) => other is Emitted && other.effect == effect;
  @override
  int get hashCode => effect.hashCode;
  @override
  String toString() => 'Emitted($effect)';
}

final class FeatureTester<S, A, E, F extends Feature<S, A, E>> {
  FeatureTester(
    this._fa,
    S initial,
    F Function(FeatureContext<S, A> featureContext) create, {
    List<SharedKey<Object?>> trackShared = const [],
    bool verifyOnTearDown = true,
  }) : cell = RootCell<S>(initial) {
    var prev = initial;
    cell.addListener(() {
      _log.add(StateChanged<S>(prev, cell.value));
      prev = cell.value;
    });
    for (final k in trackShared) {
      final sh = shared(k);
      var p = sh.value;
      sh.addListener(() {
        _log.add(SharedChanged(k, p, sh.value));
        p = sh.value;
      });
    }
    feature = create(
      FeatureContext<S, A>.detached(cell, shared: shared, onTaskAction: (a) => _log.add(Received<A>(a))),
    );
    feature.effects.addListener(() => _log.addAll(feature.effects.drain().map(Emitted<E>.new)));
    _fa.flushMicrotasks();
    if (verifyOnTearDown) m.addTearDown(finish);
  }

  final FakeAsync _fa;
  final RootCell<S> cell;
  final SharedStore shared = SharedStore();
  late final F feature;
  final List<Observed> _log = [];

  S get state => cell.value;
  List<Observed> get unasserted => List.unmodifiable(_log);

  void send(A action, [S Function(S before)? expected]) {
    _requireNothingUnasserted('before send($action)');
    final before = cell.value;
    feature.send(action);
    _fa.flushMicrotasks();
    if (expected != null) _expectStateChange(before, expected(before), 'send($action)');
  }

  void receive(A action, [S Function(S before)? expected]) {
    _expectNext(Received<A>(action));
    if (expected == null) return;
    final before = _log.whereType<StateChanged<S>>().firstOrNull?.prev ?? cell.value;
    _expectStateChange(before, expected(before), 'receive($action)');
  }

  void expectEffect(E effect) => _expectNext(Emitted<E>(effect));

  /// Asserts a State change that did not come from an action (for example, from combineWith).
  /// Kept apart from send / receive so a change no action caused is never silently folded into one.
  void expectState(S Function(S before) expected) {
    final head = _log.firstOrNull;
    if (head is! StateChanged<S>) m.fail('expected a state change, but got ${head ?? 'nothing'}');
    final before = head.prev;
    var after = before;
    while (_log.isNotEmpty && _log.first is StateChanged<S>) {
      after = (_log.removeAt(0) as StateChanged<S>).next;
    }
    m.expect(after, expected(before), reason: 'state after external change');
  }

  void expectShared<T>(SharedKey<T> key, T prev, T next) => _expectNext(SharedChanged(key, prev, next));

  void advance(Duration d) => _fa.elapse(d);

  /// Takes a reason so the test records why it skipped exhaustive checking.
  void skipUnasserted(String reason) => _log.clear();

  void _expectStateChange(S before, S expected, String what) {
    // Shared changes and effects stay in the log so they are asserted one by one, not skipped with the State check.
    final mine = <StateChanged<S>>[];
    for (var i = 0; i < _log.length;) {
      final o = _log[i];
      if (o is Received) break;
      if (o is StateChanged<S>) {
        mine.add(o);
        _log.removeAt(i);
      } else {
        i++;
      }
    }
    final after = mine.isEmpty ? before : mine.last.next;
    m.expect(after, expected, reason: 'state after $what');
  }

  void _expectNext(Object? matcher) {
    if (_log.isEmpty) m.fail('expected $matcher, but nothing else happened');
    final head = _log.removeAt(0);
    m.expect(head, matcher);
  }

  void _requireNothingUnasserted(String when) {
    if (_log.isEmpty) return;
    final lines = _log.map((o) => '  - $o').join('\n');
    _log.clear();
    m.fail('Unasserted events $when:\n$lines');
  }

  bool _finished = false;

  void finish() {
    if (_finished) return;
    _finished = true;
    final problems = <String>[];
    if (_log.isNotEmpty) problems.add('unasserted events:\n${_log.map((o) => '  - $o').join('\n')}');
    if (feature.hasRunningTasks) problems.add('tasks still running (cancel them or advance time)');
    if (_fa.pendingTimers.isNotEmpty) {
      problems.add(
        'pending timers:\n${_fa.pendingTimers.map((tm) => '  - ${tm.duration} periodic=${tm.isPeriodic}').join('\n')}',
      );
    }
    if (_fa.microtaskCount != 0) problems.add('pending microtasks: ${_fa.microtaskCount}');
    feature.dispose();
    _fa.flushMicrotasks();
    cell.dispose();
    shared.dispose();
    if (problems.isNotEmpty) m.fail('FeatureTester: test ended with\n${problems.join('\n')}');
  }
}
