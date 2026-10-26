import 'dart:async';

final class Cancelled implements Exception {
  const Cancelled();
}

final class Lifetime {
  final Completer<Never> _done = Completer<Never>();
  final List<void Function()> _onCancel = [];
  bool _cancelled = false;

  void onCancel(void Function() cb) => _cancelled ? cb() : _onCancel.add(cb);

  /// Does not stop the original Future (use [onCancel] for that); it only releases the waiter immediately.
  Future<T> guard<T>(Future<T> f) => _cancelled ? Future<T>.error(const Cancelled()) : Future.any<T>([f, _done.future]);

  /// Not Future.delayed, whose Timer would survive cancellation.
  Future<void> delay(Duration d) {
    final c = Completer<void>();
    final timer = Timer(d, c.complete);
    onCancel(timer.cancel);
    return guard(c.future);
  }

  void _cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _done.future.ignore();
    _done.completeError(const Cancelled());
    for (final cb in _onCancel.reversed) {
      cb();
    }
    _onCancel.clear();
  }
}

/// A Stream, because StreamSubscription.cancel is the only way in Dart to stop the work itself
/// (an async* body stops at its next yield and runs its finally blocks).
typedef Task<A> = Stream<A> Function(Lifetime life);

final class TaskRunner<A> {
  TaskRunner(this._send);
  final void Function(A) _send;
  final Map<Object, (Lifetime, StreamSubscription<A>)> _running = {};
  bool _disposed = false;

  bool get isIdle => _running.isEmpty;

  void run(Task<A> task, {Object? id}) {
    if (_disposed) return;
    final key = id ?? Object();
    cancel(key);
    final life = Lifetime();
    late final StreamSubscription<A> sub;
    sub = task(life).listen(
      (a) => life._cancelled ? null : _send(a),
      onError: _report,
      onDone: () {
        if (identical(_running[key]?.$2, sub)) _running.remove(key);
      },
    );
    _running[key] = (life, sub);
  }

  /// Does not wait for the old task's finally; otherwise the replacing task would be held up by its cleanup.
  void cancel(Object id) {
    final r = _running.remove(id);
    if (r == null) return;
    r.$1._cancel();
    r.$2.cancel().catchError(_report);
  }

  void dispose() {
    _disposed = true;
    for (final id in _running.keys.toList()) {
      cancel(id);
    }
  }

  static void _report(Object e, StackTrace st) {
    if (e is! Cancelled) Zone.current.handleUncaughtError(e, st);
  }
}
