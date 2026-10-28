# AGENTS.md

## Repo state
- Single-package Flutter app (`kotemal_app`), Dart `^3.12.2`; verified with Flutter 3.44.9 stable. Not a git repo (no `.git`).
- Feature-first layout: real base code in `lib/core/{constants,services,utils}`; `lib/features/{auth,menu,cart,delivery,orders,admin}/{data,domain,presentation}` contain only `.gitkeep` placeholders, no feature code yet.
- `lib/main.dart` initializes Supabase through `SupabaseService`, wraps the app in `ProviderScope`, and shows a branded welcome screen. `flutter_map` is declared but not used yet; map, auth, cart, and order flows are unimplemented.
- No CI, no pre-commit hooks, no codegen (`build_runner`/`freezed`/`json_serializable`).

## Commands
- `flutter pub get`
- `flutter run` (IDE config: `.idea/runConfigurations/main_dart.xml`); requires the Supabase defines below.
- `flutter analyze` — the only lint/typecheck step; must stay clean. Uses stock `flutter_lints`.
- `flutter test`
- Single test: `flutter test test/widget_test.dart --plain-name "muestra la pantalla inicial de K'OTEMAL"`

## Supabase config
- No `.env` or committed credentials. `ApiConstants` reads compile-time values:
  `flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>`
- `SupabaseService.initialize()` throws a `StateError` when either define is missing, so plain `flutter run` exits at startup until configured.
- Use `publishableKey` (the former anon key); `anonKey` is deprecated in `supabase_flutter` 2.18.3.
- `test/widget_test.dart` pumps `KotemalApp` directly and never calls `main()`, deliberately avoiding Supabase initialization in tests.

## Gotchas
- Android id/namespace are placeholders (`com.example.kotemal_app`) and release builds use the debug signing key (`android/app/build.gradle.kts`).
- Foreground location permissions are declared for Android, iOS, and macOS. Background tracking is not configured; add `ACCESS_BACKGROUND_LOCATION` and the iOS "always" usage key first.
- macOS entitlements include `network.client` and location; preserve both when editing `macos/Runner/*.entitlements`.
- Platform folders are Flutter-generated; do not hand-edit `**/generated_plugin_registrant*` or `ios|macos/Flutter/ephemeral/`. `.metadata` marks `lib/main.dart` and `ios/Runner.xcodeproj/project.pbxproj` as unmanaged, so `flutter migrate` skips them.
- `Formatters.currency` defaults to the `Q` symbol; change it if the target market differs.
