import 'package:flutter/foundation.dart';

/// Effects are events, not State, so equal consecutive effects are not deduplicated.
/// Effects emitted before a listener attaches are kept for the first consumer that drains them (one consumer expected).
final class EffectChannel<E> extends ChangeNotifier {
  final List<E> _pending = [];
  bool _closed = false;

  bool get hasPending => _pending.isNotEmpty;

  void emit(E effect) {
    if (_closed) return;
    _pending.add(effect);
    notifyListeners();
  }

  List<E> drain() {
    final out = List<E>.of(_pending);
    _pending.clear();
    return out;
  }

  @override
  void dispose() {
    _closed = true;
    _pending.clear();
    super.dispose();
  }
}
