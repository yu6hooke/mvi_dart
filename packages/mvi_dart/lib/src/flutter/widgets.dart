import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/feature.dart';
import '../core/shared.dart';
import '../core/store.dart';

/// Place above the Navigator. Below it, modal routes (in the overlay) cannot see the root or shared values.
class RootStore<S, A, F extends Feature<S, A, Object?>> extends StatefulWidget {
  const RootStore({super.key, required this.initial, required this.create, required this.builder, this.shared});
  final S initial;
  final F Function(FeatureContext<S, A> featureContext) create;
  final SharedStore? shared;
  final Widget Function(BuildContext context, F feature) builder;

  @override
  State<RootStore<S, A, F>> createState() => _RootStoreState<S, A, F>();
}

class _RootStoreState<S, A, F extends Feature<S, A, Object?>> extends State<RootStore<S, A, F>> {
  late final RootCell<S> _cell = RootCell<S>(widget.initial);
  late final SharedStore _shared = widget.shared ?? SharedStore();
  late final F _feature = widget.create(FeatureContext<S, A>(cell: _cell, upstream: (_) {}, shared: _shared));

  @override
  void dispose() {
    _feature.dispose();
    _cell.dispose();
    if (widget.shared == null) _shared.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SharedScope(
    store: _shared,
    child: _FeatureRef<F>(
      feature: _feature,
      child: Builder(builder: (c) => widget.builder(c, _feature)),
    ),
  );
}

extension FeatureScopes<S, A> on Feature<S, A, Object?> {
  /// A method on the parent so that the lens, wrapAction, and create types are checked against the parent's S/A
  /// at compile time.
  Widget scope<CS, CA, F extends Feature<CS, CA, Object?>>({
    Key? key,
    required Lens<S, CS> lens,
    required A Function(CA) wrapAction,
    required F Function(FeatureContext<CS, CA> featureContext) create,
    required Widget Function(BuildContext context, F feature) builder,
  }) => _FeatureScope<S, A, CS, CA, F>(
    key: key,
    parent: this,
    lens: lens,
    wrapAction: wrapAction,
    create: create,
    builder: builder,
  );
}

class _FeatureScope<PS, PA, S, A, F extends Feature<S, A, Object?>> extends StatefulWidget {
  const _FeatureScope({
    super.key,
    required this.parent,
    required this.lens,
    required this.wrapAction,
    required this.create,
    required this.builder,
  });
  final Feature<PS, PA, Object?> parent;
  final Lens<PS, S> lens;
  final PA Function(A) wrapAction;
  final F Function(FeatureContext<S, A> featureContext) create;
  final Widget Function(BuildContext context, F feature) builder;

  @override
  State<_FeatureScope<PS, PA, S, A, F>> createState() => _FeatureScopeState<PS, PA, S, A, F>();
}

class _FeatureScopeState<PS, PA, S, A, F extends Feature<S, A, Object?>> extends State<_FeatureScope<PS, PA, S, A, F>> {
  late final LensCell<PS, S> _cell = LensCell<PS, S>(widget.parent.cell, widget.lens);
  late final F _feature = widget.create(
    FeatureContext<S, A>(
      cell: _cell,
      upstream: (a) =>
          widget.parent.send(widget.wrapAction(a)), // read on each call to follow a wrapAction replaced by a rebuild
      shared: widget.parent.shared,
    ),
  );

  @override
  void didUpdateWidget(_FeatureScope<PS, PA, S, A, F> old) {
    super.didUpdateWidget(old);
    _cell.lens = widget.lens;
  }

  @override
  void dispose() {
    _feature.dispose();
    _cell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FeatureRef<F>(
    feature: _feature,
    child: Builder(builder: (c) => widget.builder(c, _feature)),
  );
}

class _SharedScope extends InheritedWidget {
  const _SharedScope({required this.store, required super.child});
  final SharedStore store;
  @override
  bool updateShouldNotify(_SharedScope old) => !identical(store, old.store);
}

class _FeatureRef<F> extends InheritedWidget {
  const _FeatureRef({required this.feature, required super.child});
  final F feature;
  @override
  bool updateShouldNotify(_FeatureRef<F> old) => !identical(feature, old.feature);
}

extension MviContext on BuildContext {
  F feature<F>() {
    final w = getInheritedWidgetOfExactType<_FeatureRef<F>>();
    assert(w != null, 'No scope of $F above $widget');
    return w!.feature;
  }

  SharedStore get sharedStore {
    final w = getInheritedWidgetOfExactType<_SharedScope>();
    assert(w != null, 'No RootStore above $widget');
    return w!.store;
  }
}

class Select<S, T> extends StatefulWidget {
  const Select(this.listenable, {super.key, required this.selector, required this.builder});
  final ValueListenable<S> listenable;
  final T Function(S state) selector;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<Select<S, T>> createState() => _SelectState<S, T>();
}

class _SelectState<S, T> extends State<Select<S, T>> {
  late T _value = widget.selector(widget.listenable.value);

  void _onChange() {
    final next = widget.selector(widget.listenable.value);
    if (next != _value) setState(() => _value = next);
  }

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onChange);
  }

  @override
  void didUpdateWidget(Select<S, T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.listenable, widget.listenable)) {
      old.listenable.removeListener(_onChange);
      widget.listenable.addListener(_onChange);
    }
    _value = widget.selector(widget.listenable.value);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// Delivery waits until after the frame so onEffect never touches Navigator or SnackBar during build.
VoidCallback listenEffects<E>(
  Feature<Object?, Object?, E> feature,
  bool Function() isMounted,
  void Function(E effect) onEffect,
) {
  var scheduled = false;
  void deliver() {
    if (scheduled) return;
    scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        scheduled = false;
        if (!isMounted()) return;
        for (final e in feature.effects.drain()) {
          onEffect(e);
        }
      })
      ..ensureVisualUpdate();
  }

  feature.effects.addListener(deliver);
  if (feature.effects.hasPending) deliver();
  return () => feature.effects.removeListener(deliver);
}

class EffectListener<E> extends StatefulWidget {
  const EffectListener(this.feature, {super.key, required this.onEffect, required this.child});
  final Feature<Object?, Object?, E> feature;
  final void Function(BuildContext context, E effect) onEffect;
  final Widget child;

  @override
  State<EffectListener<E>> createState() => _EffectListenerState<E>();
}

class _EffectListenerState<E> extends State<EffectListener<E>> {
  VoidCallback? _cancel;

  void _listen() {
    _cancel?.call();
    _cancel = listenEffects<E>(widget.feature, () => mounted, (e) => widget.onEffect(context, e));
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(EffectListener<E> old) {
    super.didUpdateWidget(old);
    if (!identical(old.feature, widget.feature)) _listen();
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
