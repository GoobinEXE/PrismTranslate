# PrismTests

Testes unitários do Prism. O target **PrismTests** está no `Prism.xcodeproj`. O GitHub Actions corre o mesmo comando a cada push e pull request em `main`.

## Como correr

No Xcode: scheme **Prism**, **⌘U** (Product → Test). Se o Prism já estiver na barra de menus, encerre-o antes — o mesmo bundle não pode ser test host e app ao mesmo tempo.

Na linha de comando, com o Xcode.app:

```bash
./scripts/test.sh
```

CI: [`.github/workflows/test.yml`](../.github/workflows/test.yml) — runner `macos-15`.

## O que está coberto

| Arquivo | Cobre |
|---------|-------|
| `HotkeyChordTests.swift` | Defaults ⌃⌥T / ⌃⌥⏎, matching de teclas/modificadores, keypad Enter, criação a partir de eventos, `displayString` |
| `LanguageMappingTests.swift` | `LanguageCode` e mapeamento DeepL / Google / Apple Translation |
| `CustomHTTPParsingTests.swift` | Extração por JSON path do provedor Custom HTTP |
| `OpenAICompatibleParsingTests.swift` | Parsing da resposta `chat/completions` |
| `TranslationErrorHTTPTests.swift` | Mensagens de HTTP 401/402/404/429 para a UI |
| `AITranslationPromptTests.swift` | Prompt de tradução por IA (fronteira e filtro) |
| `AppReleaseTests.swift` | SemVer, resumo do CHANGELOG, licença e GitHub Releases |

Os testes usam `@testable import Prism`. O target do app tem **Enable Testability** em Debug.
