import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:mvi_dart/mvi_dart.dart';

import '../hooks.dart';
import 'remaining_count.dart';

class RemainingBadge extends HookWidget {
  const RemainingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useSelect(context.sharedStore(remainingCount), (v) => v);
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Center(child: Text('$count left', key: const Key('remaining'))),
    );
  }
}
