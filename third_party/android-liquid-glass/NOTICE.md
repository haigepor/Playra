# AndroidLiquidGlass / Backdrop

Official library: `io.github.kyant0:backdrop:2.0.1` (Maven Central).

Upstream: https://github.com/Kyant0/AndroidLiquidGlass

Pinned example source: `65ab177e90e5c1d8c62e70cf7755841982da65f6`.

The Android application uses the complete official Backdrop library. These
catalog example files are copied from that revision into the original package:

- `components/LiquidBottomTabs.kt`
- `components/LiquidBottomTab.kt`
- `utils/DampedDragAnimation.kt`
- `utils/InteractiveHighlight.kt`
- `utils/DragGestureInspector.kt`

`utils/Coroutines.kt` uses the upstream Android implementation with the
Kotlin Multiplatform `actual` modifier removed and the imported Android frame
function explicitly aliased for this single-platform application.

The upstream Apache-2.0 license is included in
`android/app/src/main/assets/licenses/android-liquid-glass.txt`.

Playra's `LiquidNavigationHost` supplies background frames from the Flutter
surface using PixelCopy, owns the Compose view lifecycle, and synchronizes
navigation, visibility and window geometry. The official lens, combined
backdrops, highlights, shadows and interaction animations remain in the
upstream library and example components.

Full native runtime-shader effects require Android API 33 or later. Other
platforms retain the Flutter navigation. The Flutter player rendering backend
is unchanged.

Build requirements: compile SDK 37 (platform package 37.0), AGP 9.1.1,
Gradle 9.3.1, and Kotlin / Compose compiler 2.4.10. Existing Flutter plugins
use legacy Kotlin/DSL mode. The published WebView 1.1.3 compatibility patch
is documented in `third_party/flutter_inappwebview_android/PLAYRA-PATCH.md`.
