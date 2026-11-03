# AGENTS.md

## Repo state
- Single-package Flutter app (`kotemal_app`), Dart `^3.12.2`, Flutter 3.44.9 stable. Git repo on `feature/nuevas-mejoras`, origin `github.com/LDavidCastro/kotemal_app`.
- No CI, pre-commit hooks, or codegen (`build_runner`/`freezed`/`json_serializable`). Only `flutter_lints` v6 with stock rules.
- `lib/main.dart` initializes Supabase, wraps the app in `ProviderScope`, and sets `MenuScreen` as home. Riverpod is used for the menu query and cart only; most screens are `StatefulWidget` + direct `Supabase.instance.client` calls. Navigation is imperative `MaterialPageRoute` (no router package).
- Features are implemented under `lib/features/{auth,menu,cart,delivery,orders,admin}`; shared services/widgets live in `lib/core`. Empty `data`/`domain` folders still contain `.gitkeep`.

## Commands
- `flutter pub get`
- `flutter analyze` — keep clean; currently reports no issues.
- `flutter test` — currently passes; see Testing.
- Run with Supabase defines:
  `flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>`
- Single test: `flutter test test/widget_test.dart --plain-name "muestra la pantalla inicial de K'OTEMAL"`

## Supabase
- `ApiConstants` reads compile-time defines; `SupabaseService.initialize()` throws `StateError` if either is missing, so plain `flutter run` exits at startup.
- Use `publishableKey` (not deprecated `anonKey`) with `supabase_flutter`.
- Schema lives only in Supabase, not this repo. Queries assume:
  - `products(id, name, category, description, price, image_url, is_available)`
  - `product_customizations(product_id, name, type, price, is_available)` where `type` is `removable|extra`
  - `profiles(id, full_name, phone, role, points)`
  - `orders(id, customer_id, total, status, delivery_type, table_number, delivery_latitude, delivery_longitude, driver_latitude, driver_longitude, delivery_notes, customer_phone, delivery_driver_id, guest_device_id, platform)`
  - `order_items(order_id, product_id, quantity, unit_price, notes)`
  - Storage bucket `menu-images`, read via public URLs.
- Conventional values: `profiles.role` = `cliente|cocinero|repartidor|admin`; order `status` = `pendiente|en cocina|en camino|entregado`; `delivery_type` = `local|para_llevar|domicilio` (Guatemala/Sololá context).
- Guest checkout inserts `customer_id: null`; RLS must allow anonymous order inserts and public menu/customization reads. Realtime uses `.stream(primaryKey: ['id'])` on `orders`/`profiles`.

## Testing
- Supabase is not initialized in widget tests. `test/widget_test.dart` pumps `CartScreen` under a `ProviderScope`; keep tests on Supabase-free widgets or mock `Supabase.instance` first. Guest checkout writes IDs through `GuestOrdersService.saveOrderId()` on both checkout paths.

## Gotchas
- `auth_screen.dart` references `assets/images/logo.png`, but there is no `assets/` directory and no `assets:` section in `pubspec.yaml`; it falls back to an icon. Declare assets in `pubspec.yaml` when adding any.
- Android background GPS is configured: foreground service (`GeolocatorLocationService`), `ACCESS_BACKGROUND_LOCATION`, notification, battery-optimization, and wake-lock permissions. iOS has only `NSLocationWhenInUseUsageDescription` and no `UIBackgroundModes`, so driver tracking is background-capable only on Android.
- In-app updates (`UpdateService`/`AppUpdateCard`) read GitHub Releases from `LDavidCastro/kotemal_app` and expect a `.apk` asset, so they are Android-oriented; the cards are hidden on web with `kIsWeb`. Android build needs desugaring, `REQUEST_INSTALL_PACKAGES`, and the `ota_update` FileProvider already in the manifest.
- Android id/namespace remain placeholders (`com.example.kotemal_app`) and release builds use the debug signing key (`android/app/build.gradle.kts`). Map `userAgentPackageName` is hardcoded as `com.kotemal.app` in map screens, inconsistent with the Android id.
- Platform folders are Flutter-generated; don't hand-edit `**/generated_plugin_registrant*` or `ios|macos/Flutter/ephemeral/`. `.metadata` marks `lib/main.dart` and `ios/Runner.xcodeproj/project.pbxproj` unmanaged.
- macOS entitlements include `network.client` and location; preserve both when editing `macos/Runner/*.entitlements`.
- UI copy and error messages are Spanish; prices use the Quetzal symbol `Q` (`Formatters.currency` default) and the restaurant base location is Sololá (`14.643973, -91.120232`).
