# App fonts

The app uses a two-font system defined in `Utilities/Theme.swift`:

- **Display / headings** — `Clash Display` (from Fontshare)
- **Body text** — `General Sans` (from Fontshare)

## Files

Static TTFs are bundled in `Ledger/Fonts/` and registered in `Info.plist` → `UIAppFonts`:

- `GeneralSans-Regular.ttf`
- `GeneralSans-Medium.ttf`
- `GeneralSans-Semibold.ttf`
- `GeneralSans-Bold.ttf`
- `ClashDisplay-Regular.ttf`
- `ClashDisplay-Medium.ttf`
- `ClashDisplay-Semibold.ttf`
- `ClashDisplay-Bold.ttf`

`AppFont.scaled(..., display: true)` uses `Clash Display`; `display: false` (the default) uses `General Sans`. `Font.custom` with `.weight()` selects the closest available static weight from the registered family.

Fonts are registered at runtime from `Ledger/Utilities/FontRegistration.swift`, so they do not need to be listed in `UIAppFonts`.

## Switching fonts

Update `AppFont.displayFamily` / `AppFont.bodyFamily` and add the matching TTFs to `Ledger/Fonts/`.
