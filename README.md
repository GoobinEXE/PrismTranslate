# Prism Translate

App de menu bar para macOS que traduz o texto do campo focado com atalhos — rápido e quase sem interface.

No sistema (Dock, barra de menus, Ajustes) o nome de display é **Prism**.

## Requisitos

- macOS 15.0+ (Sequoia) — necessário para Apple Translation
- Xcode 16+
- Permissões de **Acessibilidade** e **Monitoramento de Entrada**

## Instalação

1. Baixe o `Prism-x.y.z.dmg` mais recente em [GitHub Releases](../../releases)
2. Abra o DMG e arraste **Prism** para **Aplicativos**
3. Abra o app — o macOS avisa que foi baixado da internet; clique em **Abrir**. Se bloquear, vá em **Ajustes do Sistema → Privacidade e Segurança** e clique em **Abrir Mesmo Assim**
4. Conceda **Acessibilidade** e **Monitoramento de Entrada** quando o onboarding pedir (Ajustes do Sistema → Privacidade e Segurança)

Para mantenedores: o processo completo de assinatura, notarização e publicação está em [RELEASING.md](RELEASING.md).

## Como abrir e rodar

1. Abra `Prism.xcodeproj` no Xcode
2. Selecione o target **Prism** e rode (⌘R)
3. Na primeira execução, autorize Acessibilidade (e Input Monitoring se o sistema pedir)
4. O ícone aparece na barra de menus (prisma)

## Uso rápido (padrão)

Sem configurar nada: o motor padrão é **Apple Translation** (on-device).

| Atalho | Ação |
|--------|------|
| `⌃⌥T` | Traduz e substitui o texto — **não envia** |
| `⌃⌥⏎` | Traduz, substitui e **envia** (simula Enter) |
| Enter | Só traduz/envia se **“Enter traduz e envia”** estiver ligado no menu |

Os atalhos usam **Control+Option** de propósito — quase não conflitam com outros apps. Dá para mudar (ou restaurar o padrão `⌃⌥T` / `⌃⌥⏎`) em **Preferências → Atalhos**.

Escolha o idioma destino no menu da barra. Ligue/desligue o app pelo toggle **Ligado**. Em Preferências, ative **Abrir no login** se quiser o app ao iniciar a sessão.

## Provedores

Em **Preferências**:

- **Apple Translation** (padrão, zero config)
- **DeepL** (API key)
- **Google Cloud Translation** (API key)
- **Groq** (IA gratuita — API key em console.groq.com)
- **Google Gemini** (IA gratuita — API key em aistudio.google.com)
- **Mistral** (IA gratuita — API key em console.mistral.ai)
- **DeepSeek** (IA — API key em platform.deepseek.com)
- **OpenRouter** (IA gratuita — API key em openrouter.ai; modelos `:free`)
- **OpenAI-compatible / LM Studio** (base URL + modelo; key opcional)
- **Custom HTTP** (URL, template JSON, path da resposta)

Chaves de API ficam no Keychain.

## Critérios de aceite — v1.0

A v1.0 está pronta quando todos os itens abaixo funcionam de ponta a ponta:

- [ ] **Traduzir / substituir** — com o foco em um campo de texto, `⌃⌥T` lê o texto, traduz e substitui no lugar (sem enviar)
- [ ] **Traduzir + enviar** — `⌃⌥⏎` traduz, substitui e simula Enter
- [ ] **Onboarding de permissões** — na primeira execução, o tutorial guia Acessibilidade e Monitoramento de Entrada, com links para Ajustes do Sistema
- [ ] **Provedores** — Apple Translation, DeepL, Google Cloud Translation, Groq, Gemini, Mistral, DeepSeek, OpenRouter, OpenAI-compatible / LM Studio e Custom HTTP selecionáveis em Preferências
- [ ] **Atalhos configuráveis** — gravar novos atalhos e restaurar os padrões `⌃⌥T` / `⌃⌥⏎` em Preferências → Atalhos
- [ ] **Abrir no login** — o toggle em Preferências registra/desregistra o login item

Fonte da verdade dos atalhos padrão: `HotkeyChord.swift` / `AppSettings.swift`.

## Roadmap

- **Localização EN**: a interface hoje é em português (Brasil); a localização para inglês (base EN + PT via String Catalog) está planejada para uma versão futura.
- **Prompt de tradução customizável (versão paga / Pro)**: permitir que o usuário edite o system prompt dos motores de IA (Groq, Gemini, Mistral, OpenRouter, OpenAI-compatible). O prompt padrão do sistema permanece o de alta fidelidade (significado, tom, dialeto, nuance). Customização de prompt é feature paga futura — não implementada na versão gratuita.

## Estrutura

```
Prism/
  App/           # Menu bar, estado, orquestração
  Hotkeys/       # CGEvent tap (atalhos + Enter)
  TextIO/        # Accessibility + fallback clipboard
  Translation/   # Protocolo e engine
  Providers/     # Apple, DeepL, Google, Groq, Gemini, Mistral, DeepSeek, OpenRouter, OpenAI, Custom HTTP
  Settings/      # Preferências
  Design/        # Tokens visuais e glifo Prism
  Utilities/     # Teclado, Keychain, permissões
```
