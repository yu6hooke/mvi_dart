import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

extension ReadProvider on BuildContext {
  /// Only `Provider<T>`: reading an autoDispose provider once would let it be disposed while the feature still uses it.
  T read<T>(Provider<T> provider) => ProviderScope.containerOf(this, listen: false).read(provider);
}
