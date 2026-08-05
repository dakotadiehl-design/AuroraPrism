# PR20 — Groups, Presets, Palettes (Reference Model)

Per `Aurora PR20-PR21 Architectural Guidance.pdf`:

- First-class UUID palettes with `PaletteType`
- `FixtureCueLevels.paletteRefs` + literals
- `PaletteResolver` in engine; broken refs → issues, no crash
- Group/palette/preset CRUD commands + panels
- Literals win over refs on same attribute
