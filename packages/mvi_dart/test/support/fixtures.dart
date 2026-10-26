import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mvi_dart/mvi_dart.dart';

enum Side { left, right }

@immutable
class ChildState {
  const ChildState({this.local = 0, this.shared = 0});
  final int local;

  /// Projected from the parent's `shared`. Storing it in both places would leave no single source of truth.
  final int shared;

  ChildState copyWith({int? local, int? shared}) =>
      ChildState(local: local ?? this.local, shared: shared ?? this.shared);

  @override
  bool operator ==(Object other) => other is ChildState && other.local == local && other.shared == shared;
  @override
  int get hashCode => Object.hash(local, shared);
  @override
  String toString() => 'Child(local: $local, shared: $shared)';
}

@immutable
class ParentState {
  const ParentState({
    this.shared = 0,
    this.left = const ChildState(),
    this.right = const ChildState(),
    this.log = const [],
  });
  final int shared;
  final ChildState left;
  final ChildState right;
  final List<String> log;

  ParentState copyWith({int? shared, ChildState? left, ChildState? right, List<String>? log}) => ParentState(
    shared: shared ?? this.shared,
    left: left ?? this.left,
    right: right ?? this.right,
    log: log ?? this.log,
  );

  ChildState child(Side side) => side == Side.left ? left : right;

  @override
  bool operator ==(Object other) =>
      other is ParentState &&
      other.shared == shared &&
      other.left == left &&
      other.right == right &&
      listEquals(other.log, log);
  @override
  int get hashCode => Object.hash(shared, left, right, Object.hashAll(log));
  @override
  String toString() => 'Parent(shared: $shared, left: $left, right: $right, log: $log)';
}

@immutable
class GrandState {
  const GrandState(this.value);
  final int value;
  @override
  bool operator ==(Object other) => other is GrandState && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => 'Grand($value)';
}

sealed class ChildAction {
  const ChildAction();
}

final class IncLocal extends ChildAction {
  const IncLocal();
}

final class IncShared extends ChildAction {
  const IncShared();
}

/// The test completes [gate] itself, so it can finish async work after the feature is disposed.
final class AsyncIncShared extends ChildAction {
  const AsyncIncShared(this.gate);
  final Future<void> gate;
}

final class Ping extends ChildAction {
  const Ping();
}

final class FromGrand extends ChildAction {
  const FromGrand(this.action);
  final GrandAction action;
}

sealed class GrandAction {
  const GrandAction();
}

final class GrandBump extends GrandAction {
  const GrandBump();
}

sealed class ParentAction {
  const ParentAction();
}

final class ChildOf extends ParentAction {
  const ChildOf(this.side, this.action);
  final Side side;
  final ChildAction action;
}

final class SetShared extends ParentAction {
  const SetShared(this.value);
  final int value;
}

@immutable
class Notice {
  const Notice(this.message);
  final String message;
  @override
  bool operator ==(Object other) => other is Notice && other.message == message;
  @override
  int get hashCode => message.hashCode;
  @override
  String toString() => 'Notice($message)';
}

final globalCount = SharedKey<int>('globalCount', 0);

Lens<ParentState, ChildState> childLens(Side side) => Lens(
  get: (p) => p.child(side).copyWith(shared: p.shared),
  set: (p, c) {
    final stored = c.copyWith(shared: 0);
    return side == Side.left ? p.copyWith(left: stored, shared: c.shared) : p.copyWith(right: stored, shared: c.shared);
  },
);

final grandLens = Lens<ChildState, GrandState>(
  get: (c) => GrandState(c.local),
  set: (c, g) => c.copyWith(local: g.value),
);

final class ParentFeature extends Feature<ParentState, ParentAction, Never> {
  ParentFeature(super.featureContext);

  @override
  void onReceive(ParentAction action) => uiState = switch (action) {
    // The child reducer already applied the action; the parent only records it.
    ChildOf(:final side, :final action) => uiState.copyWith(
      log: [...uiState.log, '${side.name}:${action.runtimeType}'],
    ),
    SetShared(:final value) => uiState.copyWith(shared: value),
  };
}

final class ChildFeature extends Feature<ChildState, ChildAction, Notice> {
  ChildFeature(super.featureContext) : global = featureContext.shared(globalCount);

  final Shared<int> global;
  final List<ChildAction> received = [];

  @override
  void onReceive(ChildAction action) {
    received.add(action);
    switch (action) {
      case IncLocal():
        uiState = uiState.copyWith(local: uiState.local + 1);
      case IncShared():
        uiState = uiState.copyWith(shared: uiState.shared + 1);
      case FromGrand(action: GrandBump()):
        uiState = uiState.copyWith(local: uiState.local + 1);
      case AsyncIncShared(:final gate):
        run((life) async* {
          await life.guard(gate);
          yield const IncShared();
        });
      case Ping():
        emit(const Notice('ping'));
    }
  }

  int incSharedAndRead() {
    uiState = uiState.copyWith(shared: uiState.shared + 1);
    return uiState.shared;
  }
}

final class GrandFeature extends Feature<GrandState, GrandAction, Never> {
  GrandFeature(super.featureContext);

  @override
  void onReceive(GrandAction action) {}
}

/// Writes go through [global] only. Writing back from State as well would loop Shared → State → Shared.
final class MirrorFeature extends Feature<GrandState, GrandAction, Notice> {
  MirrorFeature(super.featureContext) : global = featureContext.shared(globalCount) {
    combineWith<int>(global, (s, v) {
      merges++;
      return GrandState(v);
    });
  }

  final Shared<int> global;
  int merges = 0;

  @override
  void onReceive(GrandAction action) {
    switch (action) {
      case GrandBump():
        global.update((v) => v + 1);
    }
  }
}

sealed class SearchAction {
  const SearchAction();
}

final class QueryChanged extends SearchAction {
  const QueryChanged(this.query);
  final String query;
  @override
  bool operator ==(Object other) => other is QueryChanged && other.query == query;
  @override
  int get hashCode => query.hashCode;
  @override
  String toString() => 'QueryChanged($query)';
}

final class ResultsLoaded extends SearchAction {
  const ResultsLoaded(this.query, this.results);
  final String query;
  final List<String> results;
  @override
  bool operator ==(Object other) =>
      other is ResultsLoaded && other.query == query && listEquals(other.results, results);
  @override
  int get hashCode => Object.hash(query, Object.hashAll(results));
  @override
  String toString() => 'ResultsLoaded($query, $results)';
}

final class Submit extends SearchAction {
  const Submit();
}

final class Submitted extends SearchAction {
  const Submitted(this.count);
  final int count;
  @override
  bool operator ==(Object other) => other is Submitted && other.count == count;
  @override
  int get hashCode => count.hashCode;
  @override
  String toString() => 'Submitted($count)';
}

@immutable
final class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.loading = false,
    this.submitting = false,
    this.submits = 0,
  });
  final String query;
  final List<String> results;
  final bool loading;
  final bool submitting;
  final int submits;

  SearchState copyWith({String? query, List<String>? results, bool? loading, bool? submitting, int? submits}) =>
      SearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        loading: loading ?? this.loading,
        submitting: submitting ?? this.submitting,
        submits: submits ?? this.submits,
      );

  @override
  bool operator ==(Object other) =>
      other is SearchState &&
      other.query == query &&
      listEquals(other.results, results) &&
      other.loading == loading &&
      other.submitting == submitting &&
      other.submits == submits;
  @override
  int get hashCode => Object.hash(query, Object.hashAll(results), loading, submitting, submits);
  @override
  String toString() => 'SearchState($query, $results, loading=$loading, submitting=$submitting, submits=$submits)';
}

abstract interface class SearchApi {
  Future<List<String>> search(String query);
}

final class SearchFeature extends Feature<SearchState, SearchAction, Never> {
  SearchFeature(super.featureContext, {required this.api});
  final SearchApi api;
  static const debounce = Duration(milliseconds: 300);
  int cleanups = 0;

  @override
  void onReceive(SearchAction action) {
    switch (action) {
      case QueryChanged(:final query):
        uiState = uiState.copyWith(query: query, loading: true);
        run(id: #search, (life) async* {
          try {
            await life.delay(debounce);
            final results = await life.guard(api.search(query));
            yield ResultsLoaded(query, results);
          } finally {
            cleanups++;
          }
        });
      case ResultsLoaded(:final results):
        uiState = uiState.copyWith(results: results, loading: false);
      case Submit() when uiState.submitting:
        return;
      case Submit():
        uiState = uiState.copyWith(submitting: true);
        run((life) async* {
          await life.delay(const Duration(seconds: 1));
          yield Submitted(uiState.submits + 1);
        });
      case Submitted(:final count):
        uiState = uiState.copyWith(submitting: false, submits: count);
    }
  }
}
