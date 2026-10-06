# Handoff

**From:** Brainstorming (all roles)
**To:** — (brainstorming in progress)

Waiting on user answers to clarifying questions. Key platform constraints to resolve before design:
- iOS sandboxing prevents access to other apps' files and caches.
- Android 11+ scoped storage; broad file access needs MANAGE_EXTERNAL_STORAGE (Play policy-restricted).
- Clearing other apps' caches is not possible for regular apps on modern Android (CLEAR_APP_CACHE is system-only); options are deep-linking to per-app storage settings or an Accessibility-service automation.
- "Untouched" must likely be based on last-modified time; last-access time is unreliable on mobile filesystems.
