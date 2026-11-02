# Repository Guidelines

## About This Project

TidalSwiftLib is a Swift package for the unofficial Tidal API: session and login, codable models, search, playlists, favorites, downloads, and metadata tagging. The [TidalSwift](https://github.com/melgu/TidalSwift) app and the [`tidal` command line tool](https://github.com/melgu/TidalSwiftCLI) depend on it, and other people can use it in their own apps. Keep it platform-agnostic: no UI code, and nothing that only one client needs.

## Project Structure & Module Organization

`Sources/TidalSwiftLib` holds the library. `Session` holds the API endpoints, grouped by area (`Album.swift`, `Playlist.swift`, `Login.swift`, …), and `Codables` the models.
`docs` holds developer notes: API research, investigations, and plans for larger changes. Check it for background before working on a related area, and add findings there that are worth keeping but don't belong in code comments.

Changes to the public API affect the app, the command line tool and outside users. Keep them source compatible where possible, and bump the version accordingly (semantic versioning, tags like `1.2.0`).

## Architecture

**Networking (`Network.swift`):** Async/await HTTP client supporting GET/POST/DELETE. All Tidal API calls go through `Session` (`Session/Session.swift`), which holds auth state and constructs requests. The login (tokens and client ID) is stored in the login keychain through `Keychain.swift`, not UserDefaults, under the `keychainService` passed to `Session`. API credentials live in `Config.swift` — treat these as sensitive.

**Downloads (`Download.swift`):** Downloads tracks, albums, artists, playlists and videos into the destination given by `DownloadOptions`, which also sets audio quality and Dolby Atmos. `Metadata` tags downloaded tracks without dependencies: `FLACTagWriter` writes Vorbis comment and picture blocks, `MP4TagWriter` uses an AVFoundation passthrough export.

**Models (`Codables/`):** `Codable` structs for every Tidal entity — `Album`, `Artist`, `Track`, `Video`, `Playlist`, login responses, etc.

The package has no dependencies.

## Build, Test, and Development Commands

- `swift build`
  Build the library.
- `xcodebuild -scheme TidalSwiftLib -destination 'platform=macOS' build`
  Build it with Xcode's toolchain, as the app does.

To work on the library together with the app or the command line tool, clone the repos next to each other. Dragging this folder into the TidalSwift Xcode project uses it in place of the released version; the command line tool's `Package.swift` can point to `../TidalSwiftLib` with `.package(path:)`.

There is no automated test suite.

## Coding Style & Naming Conventions

Indent with tabs, one per level, never spaces. Xcode and many tools default to four spaces, so check new code. `.editorconfig` encodes this for editors that support it.
Types use `UpperCamelCase`; functions/properties use `lowerCamelCase`; file names match the primary type/feature.
Prefer `async/await` over callback-style APIs.
Never mess with indentation or whitespace on unrelated lines, but make sure that new or edited blocks have correct indentation.
Blank lines inside a type or function carry the indentation of the surrounding block (e.g. a single tab between two methods), they are not left empty. Only blank lines at the top level of a file are empty. Editors and tools tend to strip this whitespace, so check the diff of new or edited code for bare blank lines (`git diff | grep -n '^+$'`).
Default Actor Isolation is set to `MainActor`, with the upcoming features of Approachable Concurrency enabled in `Package.swift`.
Log with OSLog instead of `print`: declare `private let logger = Logger(category: "<FileName>")` per file, using the `Logger(category:)` init in `Logger.swift` (subsystem `de.melgu.TidalSwiftLib`). The library must not write to stdout, as a command line tool's output would break. Log tokens, credentials and request headers only with `privacy: .private`, never `.public`; `Network` logs bodies and responses only in debug builds, with secrets redacted.

## Commit & Pull Request Guidelines

Match the existing commit style: short, imperative, and specific (`Fix login`, `Add video downloads`).
Keep commits scoped to one logical change.
PRs should include:
- concise summary of user-visible/technical changes
- linked issue (if available)
- manual test notes

## Security & Configuration Tips

Do not add personal tokens, account data, or local secrets to commits.
Treat auth/config constants in `Config.swift` as sensitive integration settings; discuss API/auth changes in the PR description.
