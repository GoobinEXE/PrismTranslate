# QuickTranslate — agent notes

## Toolchain

Use **somente** o Xcode.app. Não rode `swiftly use xcode` neste projeto — isso recria
`~/Library/Developer/Toolchains/xcode.xctoolchain` e o SourceKit reclama de toolchain
duplicada (`com.apple.dt.toolchain.XcodeDefault` already registered).

## Build (sempre via Xcode.app)

Use o mesmo DerivedData do Xcode (melhor para SourceKit-LSP + debug no Cursor):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project QuickTranslate.xcodeproj \
  -scheme QuickTranslate \
  -configuration Debug \
  build
```

Não use `/usr/bin/xcodebuild` / `/usr/bin/xcrun` se falharem com erro `arm64` vs `arm64e` — chame os binários dentro de `Xcode.app`.

## SourceKit-LSP no Cursor

Já existe `buildServer.json` (via `xcode-build-server`). Após mudar o `.xcodeproj` ou adicionar arquivos Swift ao target:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcode-build-server config -project QuickTranslate.xcodeproj -scheme QuickTranslate
```

Depois: **Developer: Reload Window** no Cursor.

## Tasks úteis (⌘⇧B / Terminal → Run Task)

- `xcodebuild: QuickTranslate (Debug)` — build padrão (⌘⇧B)
- `xcode-build-server: configure` — regenera índice LSP
- `open: Xcode` — abre o `.xcodeproj`

## Debug

Launch config **QuickTranslate** (F5) usa `lldb-dap` + build prévio.
