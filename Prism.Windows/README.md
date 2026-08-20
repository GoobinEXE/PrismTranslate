# Prism for Windows (MVP)

Port nativo do Prism (Prisma Tradutor) para Windows — **C# / .NET 8**, com UI planeada em **WinUI 3 + Fluent Design**.

## Ambiente actual

Este repositório inclui o **núcleo portável** completo e providers HTTP. A shell WinUI 3 (system tray, flyout, Configurações) precisa de um **PC Windows** com Visual Studio 2022 + Windows App SDK para compilar e correr a UI.

Neste host Linux (Cloud Agent) podes:

```powershell
cd Prism.Windows
dotnet restore
dotnet build
dotnet test
```

## Estrutura

```
Prism.Windows/
  Prism.Windows.sln
  src/
    Prism.Core/         # policy, orchestrator, engine, settings, hotkeys, language
    Prism.Providers/    # Azure, DeepL, Google, OpenAI-compatible, Custom HTTP
    Prism.Platform/     # abstrações + stubs (UIA/hotkeys reais → Windows)
    Prism.App/          # scaffold WinUI (implementação na máquina Windows)
  tests/
    Prism.Core.Tests/   # xUnit — paridade com PrismTests macOS
```

## Paridade funcional (já no Core)

| Comportamento macOS | Estado Windows Core |
|---|---|
| Dois pares incoming / outgoing | ✅ |
| `TranslationActionPolicy` (painel vs replace) | ✅ |
| Orchestrator + heurística Discord + retry | ✅ |
| Cache LRU do motor | ✅ |
| Providers DeepL / Google / OpenAI / Custom HTTP | ✅ |
| Azure Translator (substitui Apple Translation) | ✅ |
| Atalhos default Ctrl+Alt+T / Enter / Y | ✅ |
| Stubs de TextIO / hotkeys para testes | ✅ |
| WinUI tray + UIA real | ⏳ requer Windows |

## Providers

| Kind | Notas |
|---|---|
| **Azure** (default) | `Azure Translator` REST v3 — key em Credential Store |
| DeepL | Free/Pro API |
| Google | Translate v2 |
| OpenAI-compatible | Ollama / LM Studio (`http://localhost:11434/v1` por defeito) |
| Custom HTTP | Template `{{text}}/{{from}}/{{to}}` |

Apple Translation **não** existe no Windows.

## Atalhos default

- **Ctrl+Alt+T** — traduzir (replace ou painel se só leitura)
- **Ctrl+Alt+Enter** — traduzir e enviar
- **Ctrl+Alt+Y** — painel (só se modo painel activo)

## Próximos passos (PC Windows)

1. Instalar [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) + Visual Studio 2022 (workload *Windows application development*) + Windows App SDK.
2. Criar projecto WinUI 3 `Prism.App` apontando para `Prism.Core` / `Prism.Providers` / `Prism.Platform`.
3. Implementar:
   - `IFocusedTextService` via **UI Automation**
   - `IGlobalHotkeyService` via `WH_KEYBOARD_LL` / `RegisterHotKey`
   - System tray + flyout Fluent
   - `NavigationView` de Configurações
   - Painel de resultado + toasts
4. Credential Manager para API keys; Startup Task para “iniciar com o Windows”.

Ver prompt de implementação completo na conversa do agente (plano MVP v1).

## Dependências

- .NET 8 SDK
- Pacote NuGet `Azure.AI.Translation.Text` (Providers)
- WinUI 3 / Windows App SDK (apenas para `Prism.App` em Windows)
