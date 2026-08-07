# QuickTranslate — agent notes

## Toolchain

Use **somente** o Xcode.app. Não rode `swiftly use xcode` neste projeto — isso recria
`~/Library/Developer/Toolchains/xcode.xctoolchain` e o SourceKit reclama de toolchain
duplicada (`com.apple.dt.toolchain.XcodeDefault` already registered).

Nesta máquina o `/usr/bin/xcrun` está quebrado (arm64 vs arm64e). Por isso o Cursor define
`SDKROOT` e `swift.SDK` explicitamente — a extensão Swift chama `xcrun --show-sdk-path`
na descoberta do toolchain e falha sem isso. Correção definitiva: reinstalar o Xcode.

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

## Cursor Cloud specific instructions

As seções acima assumem uma máquina **macOS local com Xcode**. O ambiente do
**Cursor Cloud é Ubuntu Linux x86_64**, sem macOS e sem Xcode — e o Xcode **não pode ser
instalado** no Linux.

Consequências (o que NÃO dá para fazer no cloud VM):

- **Build/run do app** (`xcodebuild`, ⌘R) e a **suíte XCTest** (`⌘U`,
  `@testable import QuickTranslate`) **não funcionam** aqui. Todo o app é macOS-only
  (menu bar / `AppKit` / `SwiftUI` / `Translation` / `Carbon` / `os.Logger`), então
  build, execução e testes exigem uma máquina **macOS + Xcode 16** (use as instruções de
  build acima nessa máquina).

O que existe e funciona no cloud VM:

- **Swift 6.1.x para Linux** instalado em `/opt/swift`, com symlinks em
  `/usr/local/bin/swift` e `/usr/local/bin/swiftc`. Serve para editar/checar sintaxe e
  rodar apenas os arquivos **independentes de plataforma** (só `import Foundation`):
  `QuickTranslate/Translation/LanguageCode.swift` e
  `QuickTranslate/Translation/TranslationProvider.swift`.
- Os `Providers/*.swift` têm lógica portável (ex.: `DeepLProvider.apiCode(...)`), mas
  usam `import os` (Apple), então **não compilam** no Linux sem editar os imports.

Smoke-test da lógica de núcleo no Linux — escreva um driver `main.swift` **fora do repo**
e compile-o junto com os fontes reais (sem modificá-los):

```bash
mkdir -p /tmp/qt-demo
cat > /tmp/qt-demo/main.swift <<'EOF'
import Foundation
print(LanguageCode.commonTargets.map(\.id))
print(ProviderKind.allCases.map(\.rawValue))
EOF
swiftc -o /tmp/qt-demo/qt-demo /tmp/qt-demo/main.swift \
  QuickTranslate/Translation/LanguageCode.swift \
  QuickTranslate/Translation/TranslationProvider.swift
/tmp/qt-demo/qt-demo
```
