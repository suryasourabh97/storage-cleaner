# Architect — decisions index

| Slug | Description | Status |
|------|-------------|--------|
| storage-cleaner | Core/app split, guarded mutation gateway, rebuildable index | Design complete (ADR-001..006) |

## Cross-cutting principles
- Pure core, thin platform adapters.
- Durable truth on disk next to the data (manifests); databases are caches.
