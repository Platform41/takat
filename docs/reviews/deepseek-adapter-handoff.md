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
   - Build `UsageSnapshot(provider: .deepseek, planName: "API", balance: Balance(amount: usd.total_balance, currency: usd.currency, isAvailable: response.is_available))`. **`planName: "API"`**, not "DeepSeek" — the pill would otherwise repeat the card header.
5. Store in `cached`, return.

Decode target models **only** those fields — nothing else from the response body.

**`Decimal` + `Codable` caveat:** `Balance.amount` is persisted in `UsageCache.Payload`. `JSONDecoder` decoding `Decimal` from a JSON number can drift precision (`12.34` → `12.34000…5`). It's invisible here — the value only ever comes from a decimal-string parse, is only displayed rounded by `.formatted(.currency)`, and is never used in arithmetic — so **plain `Decimal` Codable is acceptable**. If you want it exact, give `Balance` a custom `Codable` that encodes `amount` as a `String`.

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
- **`FixtureUsageProvider.swift`** — add `case .deepseek`: `planName = "API"`, percents/reset `nil`, `tokenPattern` unused (empty daily), and set a fixture `balance` (e.g. `Balance(amount: 4.20, currency: "USD", isAvailable: true)`). `FixtureUsageProvider.fixture` will need to thread a `balance` through — extend its internal switch.
- **`ProviderMark.swift`** must read at **12 pt** in the switcher (the Gemini mark needed a rework for exactly this) — verify at size 12, not just 24.

---

## Part 5 — `ProviderCardView` balance layout (Two)

`ProviderCardView` in `DashboardView.swift` currently has a **2-way** body branch: `sessionPercent == nil && weeklyPercent == nil` → the "limits aren't reported" caption, else → the two `UsageBar`s. DeepSeek has both percents `nil`, so **without a change it would show "Session and weekly limits aren't reported by DeepSeek"** — wrong.

Make it **3-way, balance checked first**:

```swift
if let balance = snapshot.balance {
    // balance treatment (below)
} else if snapshot.sessionPercent == nil && snapshot.weeklyPercent == nil {
    Text("Session and weekly limits aren't reported by \(snapshot.provider.displayName).")  // unchanged
} else {
    UsageBar(title: "Session", …); UsageBar(title: "Weekly", …)                             // unchanged
}
```

Balance treatment:
```
DeepSeek                                    API      ← header (mark + name) + planName pill "API"
Updated 3m ago                                        ← existing freshnessRow
$4.20 remaining                                       ← balance.amount.formatted(.currency(code: balance.currency)), .title3.weight(.semibold)
Balance OK                                            ← balance.isAvailable ? "Balance OK" .secondary : "Low — top up" .orange
```

- **The `DailyUsageChart(...)` at the bottom of the card body is currently unconditional** — wrap it: `if !snapshot.dailyTokenUsage.isEmpty { DailyUsageChart(…) }`. Otherwise DeepSeek shows a spurious "No usage in the last 7 days".
- The `if let resetDate` line is already conditional — nil for DeepSeek, no change.
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
- A "key exists" check: `KeychainStore.get("deepseek") != nil` (reading the app's own item is silent on the **signed** build; on an ad-hoc `swift run` / `build-app.sh` dev build the signing identity changes per build so macOS may show a one-time keychain prompt — expected, dev-only).

Also wire `DeepSeekUsageProvider()` into `TakatApp.swift`'s provider array.

### Optional (same file, cheap) — version in the footer

Add a line to the `SettingsView` footer: `Takat \(CFBundleShortVersionString) (build \(CFBundleVersion))` from `Bundle.main.infoDictionary`. Would have caught last session's "you're running a stale build 34" confusion in five seconds.

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
- **Maintainer needs a DeepSeek API key ready** — platform.deepseek.com → API Keys. (An account with a real balance makes the screenshot meaningful; a $0 account still exercises the "Low — top up" path.)
- Real run: enter the key in Settings, confirm the card shows the real balance + status, remove the key and confirm the card + switcher segment disappear. **Screenshot** the DeepSeek card and the Settings section.
- One re-reviews from remote; Two reviews the card layout.
