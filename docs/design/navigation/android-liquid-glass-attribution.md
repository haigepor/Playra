# AndroidLiquidGlass attribution

This project integrates the sample `LiquidBottomTabs` / `LiquidBottomTab` components and the `backdrop` library from:

- https://github.com/Kyant0/AndroidLiquidGlass
- Maven: `io.github.kyant0:backdrop:2.0.1`

The upstream project is licensed under the Apache License 2.0. The local Android copies live under:

- `android/app/src/main/kotlin/com/kyant/backdrop/catalog/components/`
- `android/app/src/main/kotlin/com/kyant/backdrop/catalog/utils/`

The Flutter bridge and host used by Playra are:

- `lib/shell/native_liquid_navigation.dart`
- `android/app/src/main/kotlin/com/example/kazumi/LiquidNavigationHost.kt`

The Flutter `PlayraBottomNav` is a fallback for Web, non-Android targets and Android versions below API 33.
