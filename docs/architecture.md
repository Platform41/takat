# Takat Architecture

## Product boundary

Takat is a macOS menu bar application. It presents usage summaries for connected AI development tools without coupling the dashboard UI to any one provider.

## Layers

```text
Menu bar scene
    -> Dashboard feature
        -> UsageStore
            -> UsageProvider adapters
                -> provider APIs or approved local data sources
```

## Initial decisions

- Native SwiftUI application
- macOS 26 (Tahoe) or later
- `MenuBarExtra` for the menu bar entry point
- Keychain for credentials and tokens
- Swift concurrency for refresh and provider calls
- Fixture provider before live integrations
- System fonts, SF Symbols, semantic colors, and accessibility labels

## Provider contract

Every provider returns the same `UsageSnapshot` model. Provider-specific authentication, rate limits, reset rules, and error states stay inside the adapter.

## Delivery order

1. Fixture-backed dashboard ✅
2. Menu bar and settings shell ✅
3. Persistence and refresh state
4. Codex adapter
5. Claude adapter
6. Accessibility, packaging, signing, and release checks
