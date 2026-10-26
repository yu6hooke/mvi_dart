import 'package:flutter/foundation.dart';

@immutable
final class const Lens<A, B>({required final B Function(A) get, required final A Function(A, B) set});

abstract interface class StateCell<S> implements ValueListenable<S> {
  void set(S next);
}

final class RootCell<S> extends ValueNotifier<S> implements StateCell<S> {
  RootCell(super.value);
  @override
  void set(S next) => value = next;
}

/// Projects from the parent on every read instead of copying. A copy would briefly return a stale value right after
/// a write to the parent.
final class LensCell<P, S> extends ChangeNotifier implements StateCell<S> {
  LensCell(this._parent, this._lens) : _last = _lens.get(_parent.value) {
    _parent.addListener(_sync);
  }
  final StateCell<P> _parent;
  Lens<P, S> _lens;
  S _last;
  bool _disposed = false;

  set lens(Lens<P, S> next) {
    if (identical(next, _lens)) return;
    _lens = next;
    _sync();
  }

  void _sync() {
    final next = _lens.get(_parent.value);
    if (next == _last) return;
    _last = next;
    notifyListeners();
  }

  @override
  S get value => _disposed ? _last : _lens.get(_parent.value);

  @override
  void set(S next) {
    if (_disposed) return; // async work that finishes after dispose must not throw
    _parent.set(_lens.set(_parent.value, next));
  }

  @override
  void dispose() {
    _disposed = true;
    _parent.removeListener(_sync);
    super.dispose();
  }
}
