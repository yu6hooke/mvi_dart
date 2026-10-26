import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvi_dart/mvi_dart.dart';
import 'package:mvi_dart_test/mvi_dart_test.dart';

import 'support/fixtures.dart';

typedef Root = ParentFeature;
typedef ChildBody = Widget Function(BuildContext context, ChildFeature f);

Widget app(Widget Function(BuildContext context, Root root) body, {SharedStore? shared}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RootStore<ParentState, ParentAction, ParentFeature>(
    initial: const ParentState(),
    create: ParentFeature.new,
    shared: shared,
    builder: (_, root) =>
        Navigator(onGenerateRoute: (_) => PageRouteBuilder<void>(pageBuilder: (c, _, _) => body(c, root))),
  ),
);

Widget childScope(Root root, Side side, ChildBody body) => root.scope(
  lens: childLens(side),
  wrapAction: (ChildAction a) => ChildOf(side, a),
  create: ChildFeature.new,
  builder: body,
);

Widget childView(ChildFeature f, Side side, {void Function()? onBuild}) => Select<ChildState, String>(
  f.state,
  selector: (s) => '${side.name}:${s.local}/${s.shared}',
  builder: (context, v) {
    onBuild?.call();
    return Text(v);
  },
);

Widget leftAndParent(BuildContext c, Root root) => Column(
  children: [
    childScope(root, Side.left, (_, f) => childView(f, Side.left)),
    Select<ParentState, int>(root.state, selector: (p) => p.shared, builder: (_, v) => Text('parent:$v')),
  ],
);

Widget both(Root root, {void Function()? onRightBuild}) => Column(
  children: [
    childScope(root, Side.left, (_, f) => childView(f, Side.left)),
    childScope(root, Side.right, (_, f) => childView(f, Side.right, onBuild: onRightBuild)),
  ],
);

ChildFeature featureAt(WidgetTester t, String textPrefix) =>
    t.element(find.textContaining(textPrefix)).feature<ChildFeature>();

ParentFeature parentOf(WidgetTester t) => t.element(find.byType(Navigator)).feature<ParentFeature>();
ParentState root(WidgetTester t) => parentOf(t).state.value;

void main() {
  testWidgets('a child write lands in the root', (t) async {
    await t.pumpWidget(app(leftAndParent));
    featureAt(t, 'left:').send(const IncLocal());
    await t.pump();
    expect(root(t).left.local, 1);
    expect(find.text('left:1/0'), findsOneWidget);
  });

  testWidgets('a child action reaches the parent once, after the child reducer', (t) async {
    await t.pumpWidget(app(leftAndParent));
    featureAt(t, 'left:').send(const IncLocal());
    await t.pump();
    expect(root(t).log, ['left:IncLocal']);
    expect(root(t).left.local, 1);
  });

  testWidgets('sibling scopes with the same State type are independent', (t) async {
    await t.pumpWidget(app((_, r) => both(r)));
    final l = featureAt(t, 'left:'), r = featureAt(t, 'right:');
    expect(identical(l, r), isFalse);
    l.send(const IncLocal());
    l.send(const IncLocal());
    r.send(const IncLocal());
    await t.pump();
    expect(root(t).left.local, 2);
    expect(root(t).right.local, 1);
  });

  testWidgets('a grandchild forwards to the same parent feature the page uses', (t) async {
    await t.pumpWidget(
      app(
        (_, r) => childScope(
          r,
          Side.left,
          (_, f) => Column(
            children: [
              childView(f, Side.left),
              f.scope(
                lens: grandLens,
                wrapAction: FromGrand.new,
                create: GrandFeature.new,
                builder: (_, _) => const Text('grand'),
              ),
            ],
          ),
        ),
      ),
    );
    final page = featureAt(t, 'left:');
    t.element(find.text('grand')).feature<GrandFeature>().send(const GrandBump());
    await t.pump();
    expect(page.received.whereType<FromGrand>(), hasLength(1));
    expect(root(t).left.local, 1);
    expect(root(t).log, ['left:FromGrand']);
  });

  testWidgets('a scope follows a new Lens after rebuild', (t) async {
    final which = ValueNotifier(Side.left);
    await t.pumpWidget(
      app(
        (_, r) => Column(
          children: [
            ValueListenableBuilder<Side>(
              valueListenable: which,
              builder: (_, side, _) => childScope(r, side, (_, f) => childView(f, side)),
            ),
          ],
        ),
      ),
    );
    which.value = Side.right;
    await t.pump();
    featureAt(t, 'right:').send(const IncLocal());
    await t.pump();
    expect(root(t).right.local, 1);
    expect(root(t).left.local, 0);
  });

  testWidgets('State read after an await includes updates made meanwhile', (t) async {
    await t.pumpWidget(app(leftAndParent));
    final f = featureAt(t, 'left:');
    final gate = Completer<void>();
    f.send(AsyncIncShared(gate.future));
    f.send(const IncShared());
    gate.complete();
    await t.pump();
    expect(root(t).shared, 2);
  });

  testWidgets('ancestor sharing via Lens: child to parent and parent to child', (t) async {
    await t.pumpWidget(app(leftAndParent));
    featureAt(t, 'left:').send(const IncShared());
    await t.pump();
    expect(root(t).shared, 1);
    expect(find.text('parent:1'), findsOneWidget);
    parentOf(t).send(const SetShared(7));
    await t.pump(); // flushes the send; no frame was scheduled yet
    await t.pump(); // renders the change
    expect(find.text('left:0/7'), findsOneWidget);
    expect(root(t).left.shared, 0, reason: 'the parent stores shared once');
  });

  testWidgets('a read right after a write in the reducer returns the new value', (t) async {
    await t.pumpWidget(app((_, r) => both(r)));
    expect(featureAt(t, 'left:').incSharedAndRead(), 1);
  });

  testWidgets('SharedKey: a separate subtree and a modal route see the same value', (t) async {
    await t.pumpWidget(
      app(
        (_, r) => Column(
          children: [
            childScope(r, Side.left, (_, _) => const Text('L')),
            Builder(
              builder: (c) =>
                  Select<int, int>(c.sharedStore(globalCount), selector: (v) => v, builder: (_, v) => Text('other:$v')),
            ),
          ],
        ),
      ),
    );
    t.element(find.text('L')).feature<ChildFeature>().global.update((v) => v + 1);
    await t.pump();
    expect(find.text('other:1'), findsOneWidget);
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      nav.push(
        RawDialogRoute<void>(
          pageBuilder: (c, _, _) =>
              Select<int, int>(c.sharedStore(globalCount), selector: (v) => v, builder: (_, v) => Text('modal:$v')),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('modal:1'), findsOneWidget);
    t.element(find.text('L')).feature<ChildFeature>().global.update((v) => v + 1);
    await t.pump();
    expect(find.text('modal:2'), findsOneWidget);
  });

  test(
    'combineWith merges a shared value into State without looping',
    () => fakeAsync((fa) {
      final h = FeatureTester<GrandState, GrandAction, Notice, MirrorFeature>(
        fa,
        const GrandState(-1),
        MirrorFeature.new,
        trackShared: [globalCount],
      );
      h.skipUnasserted('initial merge (-1 → 0)');
      h.shared(globalCount).value = 5;
      expect(h.state, const GrandState(5));
      h.skipUnasserted('external write is covered in feature_test');
      h.send(const GrandBump(), (_) => const GrandState(6));
      h.expectShared(globalCount, 5, 6);
      expect(h.feature.merges, 3, reason: 'initial, external, own: three merges');
    }),
  );

  testWidgets('each root has its own SharedStore (1/2)', (t) async {
    await t.pumpWidget(app((_, r) => childScope(r, Side.left, (_, _) => const Text('L'))));
    t.element(find.text('L')).feature<ChildFeature>().global.value = 42;
    expect(t.element(find.text('L')).sharedStore(globalCount).value, 42);
  });

  testWidgets('each root has its own SharedStore (2/2)', (t) async {
    await t.pumpWidget(app((_, r) => childScope(r, Side.left, (_, _) => const Text('L'))));
    expect(t.element(find.text('L')).sharedStore(globalCount).value, 0);
  });

  testWidgets('emitting the same effect twice delivers it twice', (t) async {
    final got = <Notice>[];
    await t.pumpWidget(
      app(
        (_, r) => childScope(
          r,
          Side.left,
          (_, f) => EffectListener<Notice>(f, onEffect: (_, e) => got.add(e), child: const Text('L')),
        ),
      ),
    );
    final f = t.element(find.text('L')).feature<ChildFeature>();
    f.send(const Ping());
    f.send(const Ping());
    await t.pump();
    expect(got, [const Notice('ping'), const Notice('ping')]);
  });

  testWidgets('an effect emitted before the listener attaches is delivered once', (t) async {
    final got = <Notice>[];
    final attach = ValueNotifier(false);
    await t.pumpWidget(
      app(
        (_, r) => childScope(
          r,
          Side.left,
          (_, f) => ValueListenableBuilder<bool>(
            valueListenable: attach,
            builder: (_, on, _) => on
                ? EffectListener<Notice>(f, onEffect: (_, e) => got.add(e), child: const Text('L'))
                : const Text('L'),
          ),
        ),
      ),
    );
    t.element(find.text('L')).feature<ChildFeature>().send(const Ping());
    attach.value = true;
    await t.pump();
    await t.pump();
    expect(got, [const Notice('ping')]);
  });

  testWidgets('an async action finishing after dispose is dropped without errors', (t) async {
    final show = ValueNotifier(true);
    await t.pumpWidget(
      app(
        (_, r) => ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, on, _) => on ? childScope(r, Side.left, (_, f) => childView(f, Side.left)) : const Text('gone'),
        ),
      ),
    );
    final gate = Completer<void>();
    featureAt(t, 'left:').send(AsyncIncShared(gate.future));
    show.value = false;
    await t.pump();
    gate.complete();
    await t.pump();
    expect(t.takeException(), isNull);
    expect(root(t).shared, 0);
  });

  testWidgets('a synchronous send from a child initState does not throw', (t) async {
    final insert = ValueNotifier(false);
    await t.pumpWidget(
      app(
        (_, r) => Column(
          children: [
            childScope(
              r,
              Side.left,
              (_, f) => ValueListenableBuilder<bool>(
                valueListenable: insert,
                builder: (_, on, _) => Column(children: [childView(f, Side.left), if (on) const _SendOnInit()]),
              ),
            ),
            childScope(r, Side.right, (_, f) => childView(f, Side.right)),
          ],
        ),
      ),
    );
    insert.value = true;
    await t.pump();
    expect(t.takeException(), isNull);
    await t.pump();
    expect(find.text('right:0/1'), findsOneWidget);
  });

  testWidgets('updating left.local does not rebuild the right view', (t) async {
    var rightBuilds = 0;
    await t.pumpWidget(app((_, r) => both(r, onRightBuild: () => rightBuilds++)));
    final before = rightBuilds;
    featureAt(t, 'left:').send(const IncLocal());
    await t.pump();
    expect(rightBuilds, before);
  });

  test(
    'a reducer can be tested without widgets',
    () => fakeAsync((fa) {
      final h = FeatureTester<ChildState, ChildAction, Notice, ChildFeature>(fa, const ChildState(), ChildFeature.new);
      h.send(const IncLocal(), (s) => s.copyWith(local: 1));
      h.send(const Ping());
      h.expectEffect(const Notice('ping'));
    }),
  );
}

class _SendOnInit extends StatefulWidget {
  const _SendOnInit();
  @override
  State<_SendOnInit> createState() => _SendOnInitState();
}

class _SendOnInitState extends State<_SendOnInit> {
  @override
  void initState() {
    super.initState();
    context.feature<ChildFeature>().send(const IncShared());
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
