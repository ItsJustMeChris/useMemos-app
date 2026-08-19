# Memos for iOS

A polished, native SwiftUI companion for a self-hosted [Memos](https://usememos.com) server. It connects directly to your instance and keeps the writing experience fast, focused, and at home on iPhone and iPad.

This is an independent client and is not an official Memos project.

## Highlights

- Personal timeline with pull-to-refresh, pagination, pins, tag filters, and native toolbar actions
- Native Markdown presentation for headings, links, quotes, code, and interactive task lists
- Create and edit private, members-only, or public memos in a keyboard-aware native composer
- Attach up to five photos to a new memo; large images are resized before upload
- Server-backed content search with tag shortcuts
- Month calendar for browsing active memos by creation date
- Archive, restore, permanently delete, and share memo text
- Fast cached reading when the server is temporarily unavailable
- System, light, and dark appearances with Dynamic Type-friendly layouts
- Secure credential storage in the iOS Keychain
- Responsive layouts for iPhone and iPad

## Requirements

- iOS or iPadOS 17.0+
- A reachable self-hosted Memos server that supports the current `/api/v1` API
- A Memos personal access token (recommended), or a username and password
- Xcode 26 recommended for development

The app has no third-party runtime dependencies.

## Run the app

1. Open `MemosNative.xcodeproj` in Xcode.
2. Select the **MemosNative** scheme.
3. Choose an iPhone or iPad simulator and press Run.

For a physical device, select your development team. The project uses the `dev.mcgravey` bundle identifier.

The checked-in Xcode project is ready to open. If you change `project.yml`, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

`project.yml` is the project configuration source of truth. Regeneration can update the generated project format based on the installed XcodeGen version.

## Connect a Memos server

Enter the normal address used to open Memos, such as `https://memos.example.com`. Do not add an API path; if `/api/v1` is supplied, the app removes it automatically. Addresses without a scheme default to HTTPS.

### Personal access token — recommended

In the Memos web app, open **Settings → Access tokens**, create a dedicated token for this iOS app, and paste it into the connection screen. Memos personal access tokens are intended for API clients and can be revoked independently.

### Username and password

The app can also use Memos password sign-in. It keeps the short-lived access token in the Keychain and uses Memos' refresh session when needed. A password is never saved by the app.

Servers that require SSO should use a personal access token; an embedded SSO browser flow is not currently included.

For a local server, enter its explicit address, for example `http://192.168.1.25:5230`. HTTPS is strongly preferred. Self-signed certificates must be trusted by iOS, and local-network behavior should be verified on a physical device.

## Privacy and offline behavior

- Credentials are stored with `AfterFirstUnlockThisDeviceOnly` Keychain protection.
- Requests travel directly between the device and the configured Memos server. There is no intermediary service.
- Credential-free timeline and archive JSON are cached inside the app's sandbox for fast launch and temporary offline reading.
- Search, calendar month loading, refresh, and all changes still require a working server connection.
- Disconnecting removes this app's credentials, connection metadata, user metadata, and memo cache from the device. It does not change anything on the server.

## App structure

- `MemosNative/App` — launch routing and the main tab shell
- `MemosNative/Core` — API client, models, session restoration, Keychain, and memo store
- `MemosNative/Design` — semantic colors and reusable visual styling
- `MemosNative/Features` — connection, timeline, calendar, composer, search, archive, settings, and Markdown UI
- `MemosNative/Resources` — app icon, brand art, and color assets
- `MemosNativeTests` — URL normalization and current API response decoding tests
- `project.yml` — canonical XcodeGen project definition

The networking layer is an actor-backed `URLSession` client. UI state uses SwiftUI Observation, and the app relies only on Apple frameworks.

## Build and test from the command line

```sh
xcodebuild -project MemosNative.xcodeproj \
  -scheme MemosNative \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

List the simulators available on your Mac:

```sh
xcodebuild -showdestinations \
  -project MemosNative.xcodeproj \
  -scheme MemosNative
```

Then run tests with one of those destinations:

```sh
xcodebuild test \
  -project MemosNative.xcodeproj \
  -scheme MemosNative \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

For visual development without a server, add `--demo-content` to the Debug scheme's launch arguments. The flag is compiled out of release builds.

## Current scope

- One active server and account at a time
- The timeline, search, and calendar are scoped to the authenticated user's memos
- The calendar shows active memos by creation date and loads each month directly from the server; archived memos are excluded
- Photo upload is available while creating a memo; existing attachments are viewable in memo detail
- No embedded SSO flow or Mac Catalyst target
- API compatibility follows current Memos `/api/v1` request and response shapes and can vary with older server versions

The relevant upstream references are the [Memos API guide](https://usememos.com/docs/integrations/api-access) and [latest API reference](https://usememos.com/docs/api/latest).
