# ADR-001: Flutter desktop with Windows APIs via Dart FFI

**Status:** Accepted
**Date:** 2026-10-07
**Feature:** storage-cleaner
**Author:** 10x-Team (Architect + Staff Engineer)

## Context
v1 targets Windows 10/11 only, but the user chose Flutter and wants a path to macOS/Android later. The app needs Windows-only APIs: known folders, drive enumeration, file attributes (OneDrive placeholders, reparse points, NTFS file IDs), `MoveFileExW`, process listing, WIC image decoding, CNG hashing, toasts and Task Scheduler.

## Decision
- Flutter desktop app. All cleaning logic lives in a **pure Dart package `cleaner_core`** with no Flutter or Windows imports; it depends only on interfaces (`PlatformFs`, `Hasher`, `ImageDecoder`, `ProcessLister`, `Clock`).
- Windows implementations of those interfaces live in the app (`lib/platform/windows/`) and call Win32 through Dart FFI using `package:win32` / `package:ffi`. No C++ plugin, except small edits to the generated Windows runner (hidden check mode).
- Tests run `cleaner_core` against in-memory and fake implementations with `dart test`.

## Alternatives Considered
| Alternative | Pros | Cons | Why Not |
|-------------|------|------|---------|
| C++ Flutter plugin for Windows APIs | Full native power, easier COM | Second language, platform channels, harder to test | FFI covers everything needed; one language |
| Native .NET (WinUI 3 / WPF) | First-class Windows APIs | Abandons Flutter choice and future portability | User chose Flutter |
| Logic inside Flutter app (no separate package) | Fewer files | Core tests need Flutter test harness; tempts UI/platform coupling | Separation enforces the safety boundary and portability |

## Consequences
### Positive
- Core logic portable and fast to test on any OS.
- Windows specifics isolated behind small interfaces.
### Negative
- COM-heavy APIs (Task Scheduler, WIC, toasts) are verbose through FFI.
### Risks
- `package:win32` coverage gaps → fall back to direct `DynamicLibrary` lookups, or the `schtasks.exe /Create /XML` CLI for Task Scheduler.

## Dependencies
- Constrains ADR-002..006: all platform effects go through `cleaner_core` interfaces.
