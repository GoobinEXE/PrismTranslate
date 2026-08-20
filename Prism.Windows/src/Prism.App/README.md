# Prism.App (WinUI 3) — scaffold

Este directório documenta a app WinUI 3. A criação do projecto WinUI (`dotnet new winui`) **só funciona em Windows** com o workload Windows App SDK instalado.

## Checklist de implementação (PC Windows)

```powershell
# Em Prism.Windows/src (no Windows):
dotnet new winui -n Prism.App -f net8.0-windows10.0.19041.0
dotnet sln ..\..\Prism.Windows.sln add Prism.App\Prism.App.csproj
dotnet add Prism.App reference ..\Prism.Core\Prism.Core.csproj
dotnet add Prism.App reference ..\Prism.Providers\Prism.Providers.csproj
dotnet add Prism.App reference ..\Prism.Platform\Prism.Platform.csproj
```

### Componentes UI a criar

1. **System tray** — `Microsoft.Windows.AppNotifications` / `NotifyIcon` ou WinUI tray helper
2. **Flyout** — ToggleSwitch + ComboBox de idiomas (Fluent, sem glass macOS)
3. **SettingsWindow** — `NavigationView` com secções: Geral, Atalhos, Tradução, Permissões, Registos, Acerca
4. **TranslationResultWindow** — tool window; Copiar / Substituir
5. **OnboardingWindow** — wizard 5–6 passos
6. **AppState** — wiring de settings → engine → orchestrator → hotkeys

### Platform Windows (implementar em `Prism.Platform`)

| Interface | API Windows |
|---|---|
| `IFocusedTextService` | UI Automation (`IUIAutomation`) + clipboard `Ctrl+C/V/A` |
| `IGlobalHotkeyService` | `SetWindowsHookEx(WH_KEYBOARD_LL)` + `SendInput` |
| `ICredentialStore` | Credential Manager / DPAPI |
| `IStartupRegistration` | StartupTask API |
| `IPermissionsService` | `ms-settings:privacy-accessibility` |

Até essas classes existirem, os stubs em `Abstractions/PlatformAbstractions.cs` permitem testes do Core em Linux/CI.
