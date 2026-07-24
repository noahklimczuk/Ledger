# App font — Inter

The app's typography uses **Inter** (see `AppFont.family` in `Utilities/Theme.swift`).
The variable font is bundled at `Ledger/Fonts/InterVariable.ttf` and registered in
`Info.plist` → `UIAppFonts`.

## Files

- `Ledger/Fonts/InterVariable.ttf` — Inter 4.1 variable font with `wght` and `opsz` axes.

## Switching to a different font

Change **one** thing: `AppFont.family` in `Utilities/Theme.swift`. Then add that
family's file to `Ledger/Fonts` and list it in `Info.plist` → `UIAppFonts`.
