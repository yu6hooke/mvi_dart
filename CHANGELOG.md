# Changelog

## 1.0.0

- First stable release. The API is unchanged from 0.3.0.
- Verified on Flutter 3.50. The supported range is unchanged: Dart 3.13+ and Flutter 3.47+.
- The example and README use `package:material_ui` instead of the deprecated `package:flutter/material.dart`.

## 0.3.0

- `FeatureFactory<S, A, F>`: the type of `create`, so a DI container can provide a fully wired feature factory.

## 0.2.0

- **Breaking:** the `FeatureContext` parameter is renamed from `ctx` to `featureContext`. Subclasses write `super.featureContext`.

## 0.1.0

- Initial release.
