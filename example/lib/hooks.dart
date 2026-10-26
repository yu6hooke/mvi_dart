// Lives in the app, not the core, so the core does not depend on flutter_hooks.
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:mvi_dart/mvi_dart.dart';

T useSelect<S, T>(ValueListenable<S> state, T Function(S s) selector) =>
    useListenableSelector(state, () => selector(state.value));

void useEffects<E>(Feature<Object?, Object?, E> feature, void Function(E effect) onEffect) {
  final context = useContext();
  final latest = useRef(onEffect)..value = onEffect;
  useEffect(() => listenEffects<E>(feature, () => context.mounted, (e) => latest.value(e)), [feature]);
}
