# DeepSeek Adapter (balance): Handoff to DeepSeek

**Spec owner:** One (architecture) · card layout = Two
**Implementer:** DeepSeek (Three)
**Branch:** `feat/deepseek-adapter` off `main` → PR (expected #32)
**Depends on:** `v0.1.0` shipped (`14da569`) — signed bundle exists, so Keychain works without a re-prompt on the release build
**Source:** `docs/research/provider-data-sources.md` § DeepSeek

## Why this one is different

Every adapter so far reads local files and reports **percentages**. DeepSeek has no CLI, no local footprint, and no usage/quota concept — it's **pay-as-you-go API credit**. The only signal is `GET /user/balance` (a dollar figure) behind an **API key**. So this adapter introduces, for the first time in Takat:

1. a network call,
2. a Keychain-stored secret + a Settings UI to enter it,
3. a **balance** concept on `UsageSnapshot` and a matching card layout.

Keep the scope tight — v1 is "$X.XX remaining" + an OK/Low status. No spend history, no sparkline.

---

## Part 1 — Model: `Balance` on `UsageSnapshot`

`Sources/Takat/Core/Models/UsageSnapshot.swift`:

```swift
public struct Balance: Equatable, Sendable, Codable {
    public let amount: Decimal
    public let currency: String        // "USD" / "CNY"
    public let isAvailable: Bool        // from is_available — false ⇒ "Low — top up"
    public init(amount: Decimal, currency: String, isAvailable: Bool) { … }
}
```

Add `public let balance: Balance?` to `UsageSnapshot` (optional, default `nil` in `init`). **No schema bump** for `UsageCache.Payload` — an optional field decodes fine from old cached files, and new files just carry it. Note it in the PR anyway.

`sessionPercent` / `weeklyPercent` / `resetDate` / `dailyTokenUsage` stay `nil`/empty for DeepSeek.

---

## Part 2 — `KeychainStore`

`Sources/Takat/Core/KeychainStore.swift` — a tiny `SecItem` wrapper for the app's **own** Generic Password items (no `keychain-access-groups` entitlement needed — that's only for *sharing* items; a non-sandboxed Developer-ID app reads/writes its own items silently once created):

```swift
enum KeychainStore {
    static let service = "net.41labs.takat.llm"
    static func get(_ account: String) -> String?
    static func set(_ account: String, _ value: String) -> Bool
    static func delete(_ account: String) -> Bool
}
```

- `kSecClass: kSecClassGenericPassword`, `kSecAttrService: service`, `kSecAttrAccount: account`.
- `set` = delete-then-add (avoid `SecItemUpdate` branching).
- `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock` (survives locked screen; fine for a background refresh).
- Never log the value.

---

## Part 3 — `DeepSeekUsageProvider`

`Sources/Takat/Core/Providers/DeepSeekUsageProvider.swift` — an **`actor`** (needs mutable state for the TTL cache; `actor` is `Sendable` so it satisfies `UsageProvider`):

```swift
public actor DeepSeekUsageProvider: UsageProvider {
    public nonisolated let providerID: ProviderID = .deepseek

    private let apiKey: @Sendable () -> String?     // default: { KeychainStore.get("deepseek") }
    private let session: URLSession                 // default: a 10s-timeout config
    private let ttl: TimeInterval = 600             // 10 min — balance changes slowly; be polite
    private var cached: (snapshot: UsageSnapshot, at: Date)?

    public func fetchUsage() async throws -> UsageSnapshot { … }
}
```

`fetchUsage()`:

1. If `cached` is younger than `ttl` → return `cached.snapshot` (the 60 s panel refresh must not hit the network every minute).
2. `guard let key = apiKey(), !key.isEmpty else { throw UsageProviderError.notConfigured }`.
3. `GET https://api.deepseek.com/user/balance`, header `Authorization: Bearer \(key)`, `Accept: application/json`.
4. Map the response:
   - `401` / `403` → `throw .unauthorized`
   - non-2xx, transport error, timeout → `throw .unavailable`
   - 2xx: decode `{ is_available: Bool, balance_infos: [{ currency, total_balance, granted_balance, topped_up_balance }] }` (balances are **JSON strings** — parse with `Decimal(string:)`, default `0`). Pick the `"USD"` entry; if none, the first entry; if `balance_infos` empty → `.unavailable`.
   - Build `UsageSnapshot(provider: .deepseek, planName: "DeepSeek", balance: Balance(amount: usd.total_balance, currency: usd.currency, isAvailable: response.is_available))`.
5. Store in `cached`, return.

Decode target models **only** those fields — nothing else from the response body.

**Error enum:** `.notConfigured` / `.unauthorized` / `.unavailable` all already exist. No new case.

---

## Part 4 — `ProviderID.deepseek` + the exhaustive switches

`ProviderID` (in `UsageSnapshot.swift`):
```swift
case deepseek
public static let displayOrder: [ProviderID] = [.claude, .codex, .gemini, .deepseek]
```

Then the compiler will flag every exhaustive switch — update all:

- **`ProviderStyle.swift`** — `displayName` → `"DeepSeek"`; `accentColor` → `.indigo` (`.blue` is Gemini's).
- **`ProviderMark.swift`** — add a `case .deepseek` mark. DeepSeek's brand is a blue whale; simplified, draw a **rounded downward chevron / droplet** or a simple whale-tail silhouette (two curves meeting at a notch). Path-drawn, single colour, same treatment as the others. Fallback: `drop.fill` SF Symbol if the path won't come out clean — note it.
- **`FixtureUsageProvider.swift`** — add `case .deepseek`: `planName = "DeepSeek"`, percents/reset `nil`, `tokenPattern` unused (empty daily), and set a fixture `balance` (e.g. `Balance(amount: 4.20, currency: "USD", isAvailable: true)`). `FixtureUsageProvider.fixture` will need to thread a `balance` through — extend its internal switch.

---

## Part 5 — `ProviderCardView` balance layout (Two)

`DashboardView.swift` — when `snapshot.balance != nil`, the card body is a **balance treatment** instead of the percent bars / caption:

```
DeepSeek                                    API
Updated 3m ago
$4.20 remaining
Balance OK                    ← or "Low — top up" (orange) when !isAvailable
```

- Amount: `snapshot.balance.amount` formatted as currency (`.formatted(.currency(code: balance.currency))`), prominent (`.title3.weight(.semibold)`).
- Status: `balance.isAvailable ? "Balance OK" (secondary) : "Low — top up" (orange)`.
- **No chart** — `dailyTokenUsage` is empty for DeepSeek; the existing `DailyUsageChart` already shows the all-zero caption, but for DeepSeek skip the chart section entirely (`if !snapshot.dailyTokenUsage.isEmpty`).
- Plan pill: show `"API"` (or omit — Two's call).
- Keep it minimal and semantic; Two refines the visual later. The spend sparkline is a **separate follow-up** (needs the persistence layer to keep a balance history).

---

## Part 6 — Settings: DeepSeek section

`SettingsView.swift` — a new `Section("DeepSeek")` below Providers:

- `SecureField("API key", text: $draftKey)` bound to `@State private var draftKey = ""` (never pre-fill from the Keychain — show a masked placeholder / status instead).
- **Save** button → `KeychainStore.set("deepseek", draftKey)`, clear `draftKey`, trigger `store.refresh()`.
- **Remove** button (only when a key exists) → `KeychainStore.delete("deepseek")`, `store.refresh()`.
- Status line:
  - no key → "Not connected"
  - key present, `store.snapshot(for: .deepseek) != nil` → "Connected"
  - key present, `store.errors[.deepseek] == .unauthorized` → "Invalid key" (orange)
  - key present, `.unavailable` → "Can't reach DeepSeek"
- Footer: "Your key is stored in the macOS Keychain and used only to read your balance from api.deepseek.com."
- A "key exists" check: `KeychainStore.get("deepseek") != nil` (reading it here is fine — it's the app's own item, silent).

Also wire `DeepSeekUsageProvider()` into `TakatApp.swift`'s provider array.

---

## Part 7 — Entitlements

No change needed. `keychain-access-groups` is **not** required for an app's own Generic Password items. Leave `App/Takat.entitlements` as-is (empty / hardened-runtime-only). If a keychain prompt ever appears on the *signed* build, revisit — but it shouldn't (stable signing identity → persistent ACL).

---

## Out of scope

- **Spend sparkline / balance history** — needs a persisted balance-reading log; separate follow-up.
- CNY formatting niceties beyond "prefer USD, else first entry".
- Key validation beyond the balance call itself (a bad key → `.unauthorized` → "Invalid key" is enough).
- `granted_balance` / `topped_up_balance` breakdown — just `total_balance` for v1.
- Any change to the other three adapters.
- Retry/backoff — one GET, `.unavailable` on failure, next refresh tries again.

---

## Security & privacy

- The API key is a **secret**: `SecureField` only, Keychain only, **never** logged, never in `UsageSnapshot`, never in the disk cache, never in an error message.
- HTTPS only (the URL is `https://`).
- The balance figure is financial — same "don't log" discipline; it does go in the snapshot + disk cache (needed for offline display), which is acceptable (local, user's own machine, same as every other snapshot).

---

## Tests

- **`KeychainStore`** — round-trip against service `"net.41labs.takat.llm.tests"` (not the real service), `set`/`get`/`delete`, cleanup in `tearDown`. Skip if the CI keychain is unavailable (it's paused anyway; local run is the gate).
- **`DeepSeekUsageProvider`** — inject `apiKey: { "test-key" }` and a mocked `URLSession` (via `URLProtocol` stub):
  - key closure returns `nil` → `.notConfigured`
  - 200 + `{ is_available: true, balance_infos: [{ currency: "USD", total_balance: "12.34", … }] }` → snapshot `balance.amount == 12.34`, `currency == "USD"`, `isAvailable`
  - 200 + only a CNY entry → uses CNY
  - 200 + empty `balance_infos` → `.unavailable`
  - 401 → `.unauthorized`; 500 → `.unavailable`; malformed body → `.unavailable`
  - two calls within `ttl` → the stub is hit **once**
- **`Balance`** — `Codable` round-trip; `UsageSnapshot` with a `balance` encodes/decodes (and an old snapshot JSON *without* `balance` still decodes → `nil`).
- **`FixtureUsageProvider`** — `.deepseek` fixture has a non-nil `balance`, nil percents.
- **`ProviderSwitcher`** — `displayOrder` now includes `.deepseek` in the right position; existing tests updated if they assert the full list.
- Keep all 79 existing tests green (some will need `.deepseek` added to `allCases` assertions).

`swift build && swift test` locally (CI paused — state result in the PR). `Package.swift` stays dependency-free (`URLSession` + `Security` are system frameworks).

## Handoff back

- Push, open the PR, fill test-evidence.
- Real run: enter a DeepSeek API key in Settings, confirm the card shows your real balance + status, remove the key and confirm the card disappears. **Screenshot** the DeepSeek card and the Settings section.
- One re-reviews from remote; Two reviews the card layout.
