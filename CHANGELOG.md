# Changelog

## 0.3.0

- `FeatureFactory<S, A, F>`: the type of `create`, so a DI container can provide a fully wired feature factory.

## 0.2.0

- **Breaking:** the `FeatureContext` parameter is renamed from `ctx` to `featureContext`. Subclasses write `super.featureContext`.

## 0.1.0

- Initial release.
