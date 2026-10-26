import 'package:flutter/foundation.dart';

/// The key owns its cells (via Expando) instead of the store holding a Map. A Map would need casts and hide type
/// mismatches until runtime.
/// Holding an Expando means a key cannot be `const`; declare keys as top-level `final`s.
/// `base` prevents `implements`, which would create keys without the Expando.
base class SharedKey<T> {
  SharedKey(this.debugName, this.initial);
  final String debugName;
  final T initial;
  final Expando<ValueNotifier<T>> _cells = Expando<ValueNotifier<T>>();

  ValueNotifier<T> _cellIn(SharedStore store) {
    assert(!store._disposed, 'SharedStore is disposed');
    return _cells[store] ??= store._own(ValueNotifier<T>(initial));
  }

  @override
  String toString() => 'SharedKey<$T>($debugName)';
}

/// Not global (one per root or per test), so values never leak between tests.
final class SharedStore {
  final List<ChangeNotifier> _owned = [];
  bool _disposed = false;

  ValueNotifier<T> _own<T>(ValueNotifier<T> n) {
    _owned.add(n);
    return n;
  }

  Shared<T> call<T>(SharedKey<T> key) => Shared<T>._(key._cellIn(this));

  void dispose() {
    _disposed = true;
    for (final n in _owned) {
      n.dispose();
    }
    _owned.clear();
  }
}

/// An extension type, so taking a reference does not allocate a wrapper.
extension type Shared<T>._(ValueNotifier<T> _cell) implements ValueListenable<T> {
  set value(T next) => _cell.value = next;
  void update(T Function(T current) f) => _cell.value = f(_cell.value);
}
