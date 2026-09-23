# Games News

Lightweight, serverless video-game news reader for Android, iOS and web. It reads three WordPress sites directly, with no backend, and merges them into one feed. The sites are never named in the UI; stories are browsed by category.

| Source | Feed | Notes |
| --- | --- | --- |
| [Wccftech](https://wccftech.com/topic/games/) | REST API, `topics=games` | The site ignores `_embed`, so featured images come from one batched `/media?include=` request per page. It also ignores the `topics` filter unless `orderby` is sent. |
| [Siliconera](https://www.siliconera.com/) | RSS (`/feed/?paged=N`) | Cloudflare answers every `/wp-json` request with HTTP 403, so the REST API is not available. The feed has full post bodies but no featured image; the lead image (or a video thumbnail) is taken from the body. |
| [PCGamesN](https://www.pcgamesn.com/) | REST API | The bare host 301-redirects to `www.`; the base URL points at `www.` directly to skip the hop. |

Adding a source is one entry in `lib/models/news_source.dart` plus one style in `lib/theme/source_style.dart`.

## App icon

`assets/icon/app_icon_512x512.png` is the Google Play hi-res icon (a lightning bolt over the word "Games" on a dark violet background). `./tool/generate_app_icons.sh` regenerates it and **every launcher icon** from the SVG sources (`app_icon.svg`, `app_icon_foreground.svg`): Android legacy and adaptive icons, all iOS sizes, and the web/PWA icons. Edit the glyph or colours in that script and re-run it. It needs Google Chrome, macOS `sips` and network access (the "Games" text uses Montserrat from Google Fonts while rendering). The splash logo is a separate file and is not touched.

## Splash screen

`SplashGate` (`lib/views/splash_screen.dart`) shows `assets/icon/splash_icon_512x512.png` (the studio logo) for 1 second, then fades into the app. The second is counted from when the logo is on screen, and the feed starts loading during it. The splash is always white, like the native launch screens (iOS `LaunchScreen.storyboard`, Android `launch_background.xml`), so the hand-off from the OS is seamless. To change the duration, pass `duration` to `SplashGate` in `lib/app.dart`.

## Navigation and categories

- A bottom bar (**Home**, **Categories**, **Bookmarks**) is visible on every screen, story pages included. Each tab has its own `Navigator` (`lib/views/main_shell.dart`), so a story opens *inside* its tab, every tab keeps its own back stack and scroll position, tapping the current tab returns to its first screen, and Android back closes the story, then returns to Home, then leaves.
- Home has an **All** tab and one tab per category: PC, PlayStation, Xbox, Nintendo, Hardware, Reviews. The Categories tab lists the same categories and jumps to one on Home.
- The sites' own taxonomies do not line up, so a story is in a category when a keyword appears as a whole word in its title or site categories/tags (`lib/models/game_category.dart`). A story can be in several; its card shows the first. Category tabs are local filters over the same merged stream, so switching costs no request.

## Run

```bash
flutter pub get
flutter run
flutter test
```

Web only: `web/sqlite3.wasm` and `web/sqflite_sw.js` (checked in) come from `dart run sqflite_common_ffi_web:setup`.

## Per-site styling

Each source has a `SourceStyle` (`lib/theme/source_style.dart`) taken from that site's own CSS:

- **Palette**, light and dark: brand colour, link colour, background, headings, body text, captions, rules (e.g. wccftech `--primary`, Siliconera `--wp--custom--*`, PCGamesN `--site-color`). Where a site's own colour is too faint for text, a lighter or darker variant of it is used; `test/source_style_test.dart` enforces a 4.5:1 contrast for every text colour.
- **Typography**: Inter (wccftech), Montserrat (Siliconera), the system font (PCGamesN), through `google_fonts`.
- **Article conventions**: Siliconera underlines links, PCGamesN sets block quotes in italics and its standfirst (`p.entry-strapline`) larger; tables get the site's rule colour.
- **Site widgets** that only make sense on the website are removed from article bodies (`NewsSource.junkSelectors`): wccftech's poll widget and Siliconera's ad-free upsell box.

The article screen wraps itself in the story's site theme (colours, fonts, link and quote style) but never shows the site's name. Bookmark and share sit in the app bar.

## Web builds

Browsers enforce CORS, and only PCGamesN sends it reliably: Siliconera's feed sends no CORS headers and wccftech's are inconsistent. On web those sources fail with an error banner (the others keep working); Android and iOS are unaffected. Fixing this needs a proxy, which this serverless app does not have.

## Before release

- Replace the Google **test** AdMob IDs: app IDs in `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`, banner unit IDs in `lib/config/app_config.dart`.
- App identifiers: Android `applicationId` / namespace `com.xufagroup.games_news`; iOS bundle id `com.xufagroup.gamesNews` (Apple does not allow underscores in bundle ids). The Dart package name is `games_news`.
- Google Fonts are downloaded on first use and cached; offline on first launch the system font is used. Bundle the font files as assets if you need them offline from the first run.

## Layout

```
lib/config     constants (caps, timeouts, ad units)
lib/models     Article, NewsSource, GameCategory
lib/db         sqflite schema, upsert, per-source 60-row purge, queries
lib/services   WordPress REST/RSS client and parsers, HTML cleaner, image cache (50 MB cap), ads, repository
lib/providers  Riverpod state (feed with per-site paging cursors, bookmarks)
lib/theme      app theme, per-site SourceStyle
lib/views      MainShell (bottom bar), Home, Categories, Article, Bookmarks
lib/widgets    cards, banner ad slot, HTML renderer, images
```

## Behaviour worth knowing

- **Merged paging.** Each site keeps its own page cursor. The *All* list only shows the window every site has fully covered, so it never has holes; scrolling fetches the next page of whichever site limits that window.
- **One site failing** (blocked, offline) does not fail the feed: the others load and a banner says some stories could not be refreshed, without naming the site.
- **Cache.** 60 unbookmarked stories are kept per site; bookmarks are never purged. The v3 database schema replaced the previous celebrity-news data (ids are now namespaced per site), so old rows and bookmarks from that app are dropped on upgrade.
