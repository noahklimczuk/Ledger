# App font — Inter

The app's typography uses **Inter** (see `AppFont.family` in `Utilities/Theme.swift`).
To make it render, add the font files to this folder, then make sure they're in the
app target (the project uses Xcode's synchronized folders, so dropping the files in
this directory includes them automatically).

## Files to add

Download Inter (SIL Open Font License, free) from https://rsms.me/inter/ or Google
Fonts, and drop these four static weights here:

- `Inter-Regular.otf`
- `Inter-Medium.otf`
- `Inter-SemiBold.otf`
- `Inter-Bold.otf`

The filenames are already registered in `Info.plist` under `UIAppFonts`. If your
files are named differently (e.g. `.ttf`), update that list to match.

## Until the files are added

Everything still builds and runs — `Font.custom` falls back to the system font (San
Francisco) when the family isn't found, so the app just uses SF until Inter is present.

## Switching to a different font

Change **one** thing: `AppFont.family` in `Utilities/Theme.swift`. Then add that
family's files here and list them in `Info.plist` → `UIAppFonts`. Nothing else needs
to change — the whole type scale is derived from that one family name.
