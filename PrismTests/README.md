# PrismTests

Testes unitários do Prism. Esta pasta **ainda não faz parte do projeto Xcode** — os arquivos foram criados fora do `.pbxproj` de propósito. Para rodá-los, adicione um target de testes uma única vez:

## Como adicionar o target de testes no Xcode

1. Abra `Prism.xcodeproj` no Xcode
2. **File → New → Target…** e escolha **Unit Testing Bundle**
3. Nomeie como `PrismTests`, com **Target to be Tested: Prism**, e confirme
4. O Xcode cria um grupo `PrismTests` com um arquivo de exemplo — pode apagar o arquivo de exemplo
5. Arraste os arquivos `*.swift` desta pasta para o grupo `PrismTests` no navegador do Xcode
   - Em "Add to targets", marque **apenas** `PrismTests` (não o app)
6. Rode com **⌘U** (Product → Test)

## O que está coberto

| Arquivo | Cobre |
|---------|-------|
| `HotkeyChordTests.swift` | Defaults ⌃⌥T / ⌃⌥⏎, matching de teclas/modificadores, keypad Enter, criação a partir de eventos, `displayString` |
| `LanguageMappingTests.swift` | `LanguageCode` (displayName, alvos comuns) e mapeamento de códigos para DeepL (ZH-HANS/ZH-HANT/PT-BR) e Google (zh-CN/zh-TW) |
| `CustomHTTPParsingTests.swift` | Extração por JSON path (`data.translations.0.text`) do provedor Custom HTTP |
| `OpenAICompatibleParsingTests.swift` | Parsing da resposta `chat/completions` (conteúdo, trimming, erros) |
| `TranslationErrorHTTPTests.swift` | Mensagens de HTTP 401/402/404/429 para a UI |
| `AppReleaseTests.swift` | SemVer, resumo do CHANGELOG, licença e avaliação de GitHub Releases |

Os testes usam `@testable import Prism`, então o target do app precisa estar com **Enable Testability** ativo em Debug (padrão do Xcode).
