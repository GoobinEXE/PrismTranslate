# QuickTranslateTests

Testes unitários do QuickTranslate. Esta pasta **ainda não faz parte do projeto Xcode** — os arquivos foram criados fora do `.pbxproj` de propósito. Para rodá-los, adicione um target de testes uma única vez:

## Como adicionar o target de testes no Xcode

1. Abra `QuickTranslate.xcodeproj` no Xcode
2. **File → New → Target…** e escolha **Unit Testing Bundle**
3. Nomeie como `QuickTranslateTests`, com **Target to be Tested: QuickTranslate**, e confirme
4. O Xcode cria um grupo `QuickTranslateTests` com um arquivo de exemplo — pode apagar o arquivo de exemplo
5. Arraste os arquivos `*.swift` desta pasta para o grupo `QuickTranslateTests` no navegador do Xcode
   - Em "Add to targets", marque **apenas** `QuickTranslateTests` (não o app)
6. Rode com **⌘U** (Product → Test)

## O que está coberto

| Arquivo | Cobre |
|---------|-------|
| `HotkeyChordTests.swift` | Defaults ⌃⌥T / ⌃⌥⏎, matching de teclas/modificadores, keypad Enter, criação a partir de eventos, `displayString` |
| `LanguageMappingTests.swift` | `LanguageCode` (displayName, alvos comuns) e mapeamento de códigos para DeepL (ZH-HANS/ZH-HANT/PT-BR) e Google (zh-CN/zh-TW) |
| `CustomHTTPParsingTests.swift` | Extração por JSON path (`data.translations.0.text`) do provedor Custom HTTP |
| `OpenAICompatibleParsingTests.swift` | Parsing da resposta `chat/completions` (conteúdo, trimming, erros) |

Os testes usam `@testable import QuickTranslate`, então o target do app precisa estar com **Enable Testability** ativo em Debug (padrão do Xcode).
