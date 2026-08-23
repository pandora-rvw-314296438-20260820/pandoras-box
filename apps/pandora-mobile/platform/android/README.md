# Android platform overlay

Pandora Mobile does not commit a full Flutter Android project. The platform
directory is materialized disposably by `flutter create` in
`.github/workflows/pandora-mobile-integration.yml`, which means anything the
generated template decides is what ships unless it is deliberately overridden.

The generated template is not acceptable for this product:

| Generated default | Owner-visible result |
|---|---|
| `NormalTheme` window background `?android:colorBackground` | Black gutters behind any translucent Flutter region in dark mode |
| `values-night` parent `Theme.Black.NoTitleBar` | Black window underlay on every dark-mode start |
| `launch_background` pinned to `@android:color/white` in both modes | White splash flash before a black window in dark mode |

This directory is copied over the generated tree after `flutter create` and
before the build, so the window underlay is deterministic:

```
android themed window underlay (@color/pandora_canvas)
  -> Porcelain or Graphite Flutter canvas (PandoraRouteBoundary)
    -> local translucent surfaces
      -> content
```

## Canvas parity is enforced

`@color/pandora_canvas` must stay byte-equal to the Dart canvas tokens in
`lib/core/design/pandora_tokens.dart`:

| Mode | Resource | Dart token |
|---|---|---|
| Light | `values/colors.xml` `#FFF6F5F2` | `PandoraPalette.porcelain.canvas` |
| Dark | `values-night/colors.xml` `#FF121317` | `PandoraPalette.graphite.canvas` |

`test/platform/android_canvas_parity_test.dart` fails the build if these drift,
so the OS underlay and the Flutter theme cannot silently disagree.

Transparency itself is not removed anywhere. The brand mark keeps its own
alpha, overlays and the navigation bar stay translucent — they simply composite
over a Pandora-owned opaque canvas instead of the bare system window.
