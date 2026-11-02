# Playra build compatibility patch

Source: published `flutter_inappwebview_android` 1.1.3 from pub.dev.

The official Backdrop 2.0.1 / Compose 1.12 dependency requires AGP 9.1 or later.
AGP 9 removes the `proguard-android.txt` default file used by this plugin.
Both build types now use `proguard-android-optimize.txt`. The plugin's existing
`-dontoptimize` behavior is retained in `android/build-proguard-rules.pro`, which
is used only for the plugin's own build. Its original consumer rules, Java and
Dart source remain unchanged. The original package license is preserved.
