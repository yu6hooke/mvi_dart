import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mvi_dart/mvi_dart.dart';
import 'package:mvi_dart_test/mvi_dart_test.dart';

import 'support/fixtures.dart';

final class FakeApi implements SearchApi {
  final List<String> calls = [];
  @override
  Future<List<String>> search(String query) {
    calls.add(query);
    return Future.delayed(const Duration(milliseconds: 100), () => ['$query-1']);
  }
}

FeatureTester<SearchState, SearchAction, Never, SearchFeature> searchTester(
  FakeAsync fa,
  FakeApi api, {
  bool verifyOnTearDown = true,
}) => FeatureTester(
  fa,
  const SearchState(),
  (featureContext) => SearchFeature(featureContext, api: api),
  verifyOnTearDown: verifyOnTearDown,
);

SearchState loading(SearchState s, String q) => s.copyWith(query: q, loading: true);

/// Sends from inside the reducer (re-entrancy) and records the processing order in State.
final class Reentrant extends Feature<List<String>, String, Never> {
  Reentrant(super.featureContext);
  @override
  void onReceive(String action) {
    uiState = [...uiState, 'start $action'];
    if (action == 'x') send('y');
    if (action == 'boom') throw StateError('boom');
    uiState = [...uiState, 'end $action'];
  }
}

List<String> texts(Element root) {
  final out = <String>[];
  void visit(Element el) {
    final w = el.widget;
    if (w is Text) out.add(w.data ?? '');
    el.visitChildren(visit);
  }

  visit(root);
  return out;
}

Widget miniApp({required Widget Function(ParentFeature root) body}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RootStore<ParentState, ParentAction, ParentFeature>(
    initial: const ParentState(),
    create: ParentFeature.new,
    builder: (_, root) => body(root),
  ),
);

Widget sharedText(ParentFeature root, String label) =>
    Select<ParentState, int>(root.state, selector: (p) => p.shared, builder: (_, v) => Text('$label:$v'));

Widget leftWithWriter(ParentFeature root) => root.scope(
  lens: childLens(Side.left),
  wrapAction: (ChildAction a) => ChildOf(Side.left, a),
  create: ChildFeature.new,
  builder: (_, _) => const _SendOnInit(),
);

void main() {
  testWidgets('send from initState during the very first build does not throw, and the view follows', (t) async {
    final reported = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) => reported.add(d.exceptionAsString().split('\n').first);
    final owner = BuildOwner(focusManager: FocusManager());
    // Reproduces runApp's path (RootWidget.attach → synchronous buildScope in the idle phase) on a separate owner.
    final rootEl = RootWidget(
      child: miniApp(body: (r) => Column(children: [sharedText(r, 'shared'), leftWithWriter(r)])),
    ).attach(owner);
    final afterAttach = texts(rootEl);
    await t.pump();
    await t.pump();
    owner.buildScope(rootEl);
    FlutterError.onError = old;
    // The separate owner has no View, so a "no render parent" error is expected and unrelated.
    final relevant = reported.where((m) => !m.startsWith('The render object for')).toList();
    expect(relevant, isEmpty);
    expect(afterAttach, ['shared:0']);
    expect(texts(rootEl), ['shared:1']);
  });

  testWidgets('a send during build does not tear: one frame sees one State', (t) async {
    final insert = ValueNotifier(false);
    await t.pumpWidget(
      miniApp(
        body: (r) => ValueListenableBuilder<bool>(
          valueListenable: insert,
          builder: (_, on, _) =>
              Column(children: [sharedText(r, 'before'), if (on) leftWithWriter(r), if (on) sharedText(r, 'after')]),
        ),
      ),
    );
    insert.value = true;
    await t.pump();
    final frame = t.widgetList<Text>(find.byType(Text)).map((w) => w.data!.split(':').last).toSet();
    expect(frame, hasLength(1));
    await t.pump();
    expect(find.text('before:1'), findsOneWidget);
    expect(find.text('after:1'), findsOneWidget);
  });

  test(
    'dispose stops running tasks immediately, even mid-await, and runs finally',
    () => fakeAsync((fa) {
      final api = FakeApi();
      final h = searchTester(fa, api, verifyOnTearDown: false);
      h.send(const QueryChanged('a'), (s) => loading(s, 'a'));
      h.advance(const Duration(milliseconds: 50)); // inside the debounce
      h.feature.dispose();
      fa.flushMicrotasks();
      expect(h.feature.cleanups, 1);
      expect(h.feature.hasRunningTasks, isFalse);
      h.advance(const Duration(seconds: 1));
      expect(api.calls, isEmpty);
      expect(h.unasserted, isEmpty);
    }),
  );

  test(
    'same id: a new run cancels the old one, so stale results never land',
    () => fakeAsync((fa) {
      final api = FakeApi();
      final h = searchTester(fa, api);
      h.send(const QueryChanged('a'), (s) => loading(s, 'a'));
      h.advance(const Duration(milliseconds: 100));
      h.send(const QueryChanged('ab'), (s) => loading(s, 'ab'));
      h.advance(const Duration(milliseconds: 400));
      h.receive(const ResultsLoaded('ab', ['ab-1']), (s) => s.copyWith(results: ['ab-1'], loading: false));
      expect(api.calls, ['ab']);
      expect(h.feature.cleanups, 2);
    }),
  );

  test(
    'dropping: the reducer ignores a second submit by checking State',
    () => fakeAsync((fa) {
      final h = searchTester(fa, FakeApi());
      h.send(const Submit(), (s) => s.copyWith(submitting: true));
      h.advance(const Duration(milliseconds: 500));
      h.send(const Submit());
      h.advance(const Duration(seconds: 1));
      h.receive(const Submitted(1), (s) => s.copyWith(submitting: false, submits: 1));
    }),
  );

  test(
    'actions run one at a time in order; a send from the reducer runs after the current action reaches the parent',
    () => fakeAsync((fa) {
      final up = <String>[];
      final cell = RootCell<List<String>>(const []);
      final f = Reentrant(FeatureContext.detached(cell, upstream: up.add));
      f.send('x');
      fa.flushMicrotasks();
      expect(cell.value, ['start x', 'end x', 'start y', 'end y']);
      expect(up, ['x', 'y']);
    }),
  );

  test('a throwing reducer restores State, is not forwarded, and later actions still run', () {
    final up = <String>[];
    final errors = <Object>[];
    final cell = RootCell<List<String>>(const []);
    runZonedGuarded(
      () => fakeAsync((fa) {
        final f = Reentrant(FeatureContext.detached(cell, upstream: up.add));
        f.send('boom');
        f.send('ok');
        fa.flushMicrotasks();
      }),
      (e, _) => errors.add(e),
    );
    expect(errors.single, isA<StateError>());
    expect(cell.value, ['start ok', 'end ok']);
    expect(up, ['ok']);
  });

  test(
    'FeatureTester fails on unasserted state changes and on running tasks',
    () => fakeAsync((fa) {
      final h = FeatureTester<ChildState, ChildAction, Notice, ChildFeature>(
        fa,
        const ChildState(),
        ChildFeature.new,
        verifyOnTearDown: false,
      );
      h.send(const IncLocal());
      expect(() => h.send(const Ping()), throwsA(isA<TestFailure>()));
      final s = searchTester(fa, FakeApi(), verifyOnTearDown: false);
      s.send(const QueryChanged('q'), (st) => loading(st, 'q'));
      expect(
        s.finish,
        throwsA(
          isA<TestFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('tasks still running'), contains('pending timers')),
          ),
        ),
      );
      h.finish();
    }),
  );

  test(
    'time is deterministic: results arrive at exactly debounce 300ms + API 100ms',
    () => fakeAsync((fa) {
      final h = searchTester(fa, FakeApi());
      h.send(const QueryChanged('z'), (s) => loading(s, 'z'));
      h.advance(const Duration(milliseconds: 399));
      expect(h.unasserted, isEmpty);
      h.advance(const Duration(milliseconds: 1));
      h.receive(const ResultsLoaded('z', ['z-1']), (s) => s.copyWith(results: ['z-1'], loading: false));
    }),
  );

  test(
    'a State change without an action (combineWith) must be asserted with expectState before the next send',
    () => fakeAsync((fa) {
      final h = FeatureTester(fa, const GrandState(0), MirrorFeature.new);
      h.shared(globalCount).value = 5;
      expect(h.unasserted, hasLength(1));
      h.expectState((_) => const GrandState(5));
      h.send(const GrandBump(), (_) => const GrandState(6));
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
