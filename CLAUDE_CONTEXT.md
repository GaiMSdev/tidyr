# Tidyr – Claude Code Context

## Prosjekt
- **Repo:** `/Users/robert/Xcode Prosjekter/Organize with AI/Tidyr/`
- **Stack:** SwiftUI/macOS 14+, `@Observable`, Gemini 2.5 Flash API, Keychain, JSON → `~/Library/Application Support/Tidyr/`
- **Build:** `xcodebuild -scheme Tidyr -destination 'platform=macOS' build`
- **XcodeGen:** Kjør `xcodegen generate` etter nye `.swift`-filer. SourceKit-feil i enkeltfiler er falske positiver — ignorer dem, sjekk med xcodebuild.

---

## Arkitektur (nøkkelfiler)

| Fil | Rolle |
|-----|-------|
| `ContentView.swift` | All UI: sidebar, FileListView, DoneView, ErrorView, CommandBar, FileRow |
| `SourceStore.swift` | @Observable store: sources, files, detailMode, history, analyse, apply, undo |
| `RuleStore.swift` | Brukerregler, persistert, injisert i prompt |
| `SafetyChecker.swift` | Blokkerer/advarer på systembaner, app-bundles, .git, Xcode-prosjekter |
| `AnalysisService.swift` | Prompt-bygging og Gemini-kall |
| `Source.swift` | Source struct med Plex-felter, Codable, id-only Hashable |
| `ChangeHistory.swift` | ChangeSession og UndoOperation, sourceURL backwards-compatible |
| `ObsidianLinkRepairer.swift` | Wikilink- og canvas-reparering |
| `PlexLibraryDetector.swift` | Plex-oppdagelse og bibliotekstype |
| `PlexSyncService.swift` | Plex refresh-kall |
| `RulesView.swift` / `HistoryView.swift` | Detaljvisninger for sidebar-elementer |
| `SettingsView.swift` | API-nøkkel + clipboard-deteksjon |

## Sidebar-navigasjon
`SidebarItem: Hashable` enum: `.source(Source)`, `.rules`, `.history`.
Rules/History bruker `.tag()` + `.onTapGesture` — NavigationLink fungerer ikke her.

---

## Alt implementert

### Kjerne
- Gemini 2.5 Flash analyse, prompt-bygging med kommando + regler + Obsidian/Plex-seksjoner
- Keychain-lagring, clipboard-deteksjon i Settings (banner for nøkler som starter med "AIza...")
- Sources persistert til `sources.json`, history til `history.json` (maks 100)
- Partial apply: hopper over konflikter, returnerer `skipped: [String]`
- Conflict pre-check med `confirmationDialog` før Apply
- Drag-drop til mappe med synlig feilmelding
- Undo fra DoneView og HistoryView, "New Folder"-knapp

### Obsidian
- Auto-deteksjon via `.obsidian/`-mappen, lilla diamant-ikon i sidebar
- `ObsidianLinkRepairer`: reparerer `[[wikilinks]]`, `![[embeds]]`, `.canvas` JSON etter flytt/rename
- Leser `.obsidian/app.json` for link-format, `reverseRepair()` ved undo
- `ChangeSession.sourceURL: URL?` for vault-identifikasjon (backwards-compatible Codable)
- Prompt-instruksjoner: renames tillatt (linker repareres), `.canvas` beskyttes

### Plex
- `PlexLibraryType` enum (movies/shows/music/photos/other), leser `.LocalAdminToken`, spør `/library/sections`
- Auto-deteksjon ved `addFolder()`, oppdaterer `sources[idx]` på `@MainActor`
- Naming conventions injiseres i prompt, refresh via `/library/sections/{id}/refresh` etter apply
- Oransje type-ikon i sidebar

### UI
- `DoneView`: skipped-count, wikilink-reparert-count (lilla), Plex-sync-status (oransje)
- `ErrorView`: "Try Again" kaller `retryLastAnalysis`
- `HistoryView`: "Clear All"-knapp, gruppert Today/Yesterday/Earlier
- `FileListView`: Undo-knapp i toolbar (kun når `canUndo`), lilla rules-indikator over CommandBar (kun når `ruleCount > 0`)

---

## Fasestatus

| Fase | Innhold | Status |
|------|---------|--------|
| Phase 1–8 | Kjerne, AI, Rules, History, Obsidian, Plex, UX-polish | ✅ Ferdig |
| Phase 9 | App Store-prep | 🔄 Neste |

---

## Gjenstår (Phase 9)

1. **App-ikon** — SVG-design ferdig på `icon-design.svg` i prosjektmappen. Konsept: 5 hvite stigende søyler (sort-metafor) + gull sparkle (AI) + "tidyr" i hvit bold tekst, på blå→lilla gradient. Trenger eksport til PNG 1024×1024 → legges i `Assets.xcassets/AppIcon.appiconset/`. Konverter med: `rsvg-convert -w 1024 -h 1024 icon-design.svg -o icon-1024.png` (krever librsvg: `brew install librsvg`).
2. **Bundle ID** — `com.tidyr.app` (bestemt). Sett i Xcode.
3. **Versjon** — Sett versjon 1.0 og build 1 i Xcode.
4. **Privacy policy** — Kreves av App Store. Tidyr sender ingen brukerdata til egne servere. Enkel side holder (GitHub Pages).
5. **App Store-tekst** — Tittel, undertittel (30 tegn), beskrivelse (4000 tegn), nøkkelord (100 tegn). Utkast finnes i samtalehistorikk.
6. **Screenshots** — Minimum 1 per skjermstørrelse. Mac: 1280×800 eller 1440×900.
7. **TestFlight** — Beta til 3–5 testbrukere før innsending.
8. **Featuring Nomination** — Send til Apple 3 måneder før lansering via App Store Connect.

---

## Planlagt feature (ikke implementert): Obsidian vault-picker

Dedikert "Add Obsidian Vault"-flyt som leser `~/Library/Application Support/obsidian/obsidian.json` og viser liste over kjente vaults. Dataformat verifisert:
```json
{ "vaults": { "<id>": { "path": "/full/path/to/vault", "ts": 1234567890, "open": true } } }
```
Implementasjon: ny fil `ObsidianVaultPicker.swift` + `SourceStore.addVault(url:)` + lilla diamant-knapp i `SidebarActionBar`.

---

## Konkurrentlandskap

| App | Pris | Svakhet |
|-----|------|---------|
| Sparkle (Every) | $5/mnd | Flytter filer uten godkjenning — Tidyrs største fordel |
| Folder Tidy | ~$8 engangs | Ingen AI |
| Easy File Organizer | Engangs | Gammel UI, ingen AI |

**Tidyrs differensiering:** Brukeren godkjenner alt, Obsidian-støtte med linkrepair, ingen løpende kostnad for utvikler.

**Anbefalt pris:** Engangs $9.99–14.99 (Sparkle tar $89 lifetime).

---

## Neste sesjon — start her

Les denne filen, deretter:

1. Konverter `icon-design.svg` til PNG og legg inn i Xcode (`brew install librsvg` → `rsvg-convert -w 1024 -h 1024 icon-design.svg -o icon-1024.png`)
2. Sett bundle ID `com.tidyr.app` og versjon 1.0 / build 1 i Xcode
3. Skriv App Store-tekst (tittel, undertittel maks 30 tegn, beskrivelse maks 4000 tegn, nøkkelord maks 100 tegn)
4. Lag privacy policy-tekst (Tidyr sender ingen brukerdata — API-nøkkelen går direkte til Google)
5. Ta screenshots (1280×800 eller 1440×900) og klargjør for TestFlight

Siste bygg: ✅ BUILD SUCCEEDED
