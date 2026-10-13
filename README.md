# LinkLauncher

Nativní macOS aplikace ve stylu Spotlightu pro rychlé otevírání vlastních odkazů.
Globální zkratka (výchozí **⌘⇧Space**) otevře plovoucí panel, napíšete část názvu
(bez ohledu na diakritiku), Enter → odkaz se otevře ve výchozím prohlížeči.

## Požadavky

- macOS 14 Sonoma a novější
- Xcode 15+ (Swift 5.9+)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Sestavení a instalace

```bash
scripts/install.sh        # build Release → /Applications/LinkLauncher.app a spuštění
```

Instalační DMG (aplikace + odkaz na složku Aplikace):

```bash
scripts/make-dmg.sh       # → build/LinkLauncher-<verze>.dmg
```

DMG se vytváří i v CI (artefakt `LinkLauncher-dmg` u každého běhu workflow).
Aplikace je podepsaná jen ad-hoc a není notarizovaná – na jiném Macu ji poprvé
otevřete přes pravý klik → Otevřít (nebo `xattr -dr com.apple.quarantine /Applications/LinkLauncher.app`).

Vývoj v Xcode:

```bash
xcodegen generate
open LinkLauncher.xcodeproj
```

Testy: `xcodebuild -project LinkLauncher.xcodeproj -scheme LinkLauncher -destination 'platform=macOS' test`

Aplikace je podepsaná ad-hoc („Sign to Run Locally“), App Sandbox je vypnutý (kvůli čtení
záložek Chrome). Při prvním spuštění se zapne spouštění po přihlášení (lze vypnout v Nastavení).

## Launcher

| Klávesa | Akce |
|---|---|
| ↑ / ↓ (⌃P / ⌃N) | výběr |
| Enter, klik | otevřít ve výchozím prohlížeči |
| ⌘1 – ⌘9 | otevřít n-tý výsledek |
| ⌘C | zkopírovat URL vybrané položky |
| ⌘E | upravit vybranou položku |
| ⌘N | nový odkaz (URL z dotazu se předvyplní) |
| Tab | doplnit navrhovaný štítek |
| Esc, klik mimo, zkratka znovu | zavřít |

Panel jde přesunout tažením za horní lištu (ikonu nebo okraj vedle pole). Pozice se
nepamatuje – při dalším otevření je launcher opět ve výchozím místě.

**Vyhledávání:** fuzzy přes název (nejvyšší váha), štítky a URL; bez ohledu na velikost
písmen a diakritiku. `#štítek` filtruje (více štítků = AND), např. `#práce jira`.
Prázdný dotaz řadí podle frecency (počet otevření × čerstvost).

## Import záložek

Okno importu (menu bar → Importovat záložky…) má dva zdroje:

**Profil Chrome** – načte záložky přímo z profilu v `~/Library/Application Support/Google/Chrome/`
(výběr profilu, jména z `Local State`). macOS se může zeptat na přístup k datům jiných
aplikací – povolte ho v Nastavení systému → Soukromí a zabezpečení.

**HTML soubor** – export záložek (formát Netscape Bookmark File) z Chrome, Safari,
Firefoxu nebo Edge:

- **Chrome:** Správce záložek (⌥⌘B) → ⋮ → Exportovat záložky
- **Safari:** Soubor → Exportovat → Záložky…
- **Firefox:** Spravovat záložky → Import a záloha → Exportovat do HTML

V okně importu soubor vyberte (nebo ho přetáhněte do okna), zaškrtněte složky/odkazy
a zvolte, zda se názvy složek mají stát štítky (nejbližší složka / celá cesta).
Duplicitní URL se přeskočí.

## Data

`~/Library/Application Support/LinkLauncher/links.json` – čitelný JSON (seřazené klíče),
vhodný pro ruční úpravy i git. Změny souboru se projeví bez restartu. Pokud soubor nejde
načíst, aplikace ho nepřepíše, vytvoří zálohu `links.broken-*.json` a zobrazí chybu.

```json
{
  "links" : [
    {
      "createdAt" : "2026-10-13T10:00:00Z",
      "id" : "8C0E0F7E-…",
      "lastOpenedAt" : "2026-10-13T10:00:00Z",
      "openCount" : 3,
      "tags" : [ "práce", "pm" ],
      "title" : "Jira",
      "url" : "https://example.atlassian.net"
    }
  ],
  "version" : 1
}
```

Štítky se ukládají malými písmeny bez mezer (mezera → `-`). Favicony se cachují
v `~/Library/Caches/LinkLauncher/favicons`.

## Struktura

```
LinkLauncher/
  App/        vstupní bod, AppDelegate, menu bar, okna, zkratka, login item
  Launcher/   NSPanel, SwiftUI view, ovládání klávesnicí
  Search/     fuzzy matching, parser dotazu (#štítky), frecency
  Manager/    okno správy odkazů a štítků, editor
  Import/     Chrome profily a parser Bookmarks, parser HTML exportu, plán importu, UI
  Settings/   nastavení
  Storage/    LinkStore (načítání, ukládání, sledování souboru), JSON kodek
  Services/   načítání titulku stránky, favicony
  Models/     Link, štítky, URL
Tests/        unit testy (Search, Import, Storage)
Config/       Info.plist, entitlements
```
