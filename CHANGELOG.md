# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o versionamento segue o [Semantic Versioning](https://semver.org/lang/pt-BR/).
A seção **Novidades** é o texto da aba Sobre (linguagem para o público). Detalhes técnicos ficam nas seções seguintes.

## [1.1.1] - 2026-11-14

Redesign da interface (visual nativo do macOS), correções de fluxo e paleta da marca Prism. Build `21`.

### Novidades

- Menu nativo no clique direito do prisma, com cinco itens: Ligado, Traduzir área de transferência, Traduções recentes (as últimas 5, para copiar de novo), Configurações e Sair
- Desfazer no aviso perto do ponteiro, logo depois de substituir o texto
- No painel, o par de idiomas vira um menu para traduzir para outro idioma ali mesmo
- Motor reserva: se DeepL, Google ou o servidor local falharem, a tradução da Apple no Mac assume e o aviso diz isso
- Configurações: apps ignorados pelos atalhos, botão para verificar a chave de API, termos que os motores de IA não traduzem e tom formal ou informal
- Menu da barra mais direto: liga/desliga no topo, avisos de permissão primeiro, modo popup sempre visível
- Copiar fecha o painel de tradução, por clique, ⌘C ou Enter
- Configuração inicial em 4 passos, com as duas permissões na mesma tela
- Cada atalho em Ajustes explica o que faz
- Cor de destaque no ciano da marca Prism
- Aba Sobre com o logo da Prism (monograma P do site, em SVG, com versão para o modo escuro)

### Changed

- Cartões de conteúdo usam preenchimento semântico do sistema (`QTCard`, antes `GlassSurface`); Liquid Glass fica no painel de resultado, no HUD e no onboarding
- `AccentColor` em `#005F85` (claro) e `#0078A8` (escuro), conforme `docs/brand/PALETTE.md`, que agora espelha os tokens do site Prism
- SVGs de `docs/readme/` recoloridos para Marfim `#F2ECE1`, tinta `#0D0F13` e `ink-cyan` `#005F85`
- Etiqueta de status do menu aparece só em "Traduzindo…", "Concluído" e "Erro"; o interruptor já indica ligado ou pausado
- Ajustes › Provedor volta a mostrar as etiquetas do motor (Grátis, Pago, IA, Local)
- Removidos textos longos de Geral, Provedor, Atalhos e Sobre, e 34 strings sem uso do catálogo

### Security

- Inclui o reforço de dados sensíveis publicado na 1.0.14 (logs, Keychain, transporte HTTP, cache e área de transferência)
- App assinado com Developer ID e notarizado pela Apple; o Homebrew instala sem o passo "Abrir Mesmo Assim"

### Fixed

- Onboarding: o pedido de Monitoramento de Entrada só acontecia depois da Acessibilidade concedida; quem seguia sem ela não encontrava o Prism na lista do sistema
- Onboarding: o checklist mandava os pacotes de idioma para Ajustes › Geral em vez de Provedor
- Menu e Ajustes › Permissões não avisavam quando faltava só a Acessibilidade
- Painel de tradução: Enter copiava e fechava, mas o clique em Copiar deixava o painel aberto
- Painel de tradução: em textos lidos via área de transferência (Discord, PDF), copiar a tradução e fechar o painel devolvia o conteúdo antigo da área de transferência 0,35 s depois
- Substituição: se a seleção sumisse durante a tradução de um trecho, o campo inteiro virava a tradução do trecho; agora nada é substituído e o erro explica o motivo
- "Enter traduz e envia": ⇧Enter (nova linha) também traduzia e enviava; Enter em campo vazio era engolido; com o painel aberto, o Enter do painel podia disparar "traduzir e enviar"
- Erros de Acessibilidade no aviso perto do ponteiro e no menu levam a Configurações › Permissões em vez de Logs
- Um segundo atalho durante uma tradução mostrava erro e fazia o menu voltar a ocioso no meio dela
- Onboarding: a janela ficava por cima dos Ajustes do Sistema; o checklist verificava só o par "texto que escrevo"
- Gravador de atalhos aceitava ⌘C, ⌘V, ⌘Z e outros atalhos de edição do macOS
- "Enter traduz e envia" traduzia de novo um texto que já estava no idioma de destino; agora só envia
- Atalho com o Prism pausado não dava nenhum retorno; agora o aviso diz que ele está pausado
- Substituir no painel com outra tradução em curso fechava o painel e perdia a tradução; agora o painel fica aberto
- No modo popup, sem seleção, o atalho podia selecionar a conversa inteira em apps como o Discord

## [1.1.0] - 2026-10-29

Bundle ID unificado: `dev.prism.tradutor` (Debug, Release, instalador e docs). Build `20`.

### Novidades

- Identificador do app alinhado para testes e distribuição (`dev.prism.tradutor`)
- Pacote Mac App Store / TestFlight: `./scripts/export-testflight.sh` gera `.pkg` para o Transporter

### Changed

- `PRODUCT_BUNDLE_IDENTIFIER` Debug/Release → `dev.prism.tradutor` (tests → `dev.prism.tradutor.tests`)
- Empacotamento (`release.sh`, `distribution.xml`), Homebrew zap, docs e fallbacks de código usam o novo ID
- Preferências/Keychain passam a viver sob `dev.prism.tradutor` (instalação antiga sob `com.marcelopessoa.prism` não migra sozinha)
- Entitlements App Store (`PrismAppStore.entitlements`, sandbox ON) separados dos de Community/Developer ID
- `ITSAppUsesNonExemptEncryption` e descrição de rede local no `Info.plist`

## [1.0.14] - 2026-08-19

Hardening de dados sensíveis: logs, Keychain, transporte HTTP e retenção em memória.

### Security

- Logs: prévias de texto desligadas por padrão (opt-in em Configurações › Logs › Privacidade); OSLog `private` em info/debug; redação expandida; aviso ao exportar.
- Keychain: `WhenUnlockedThisDeviceOnly`; headers Custom HTTP migrados do UserDefaults; credenciais efémeras (`SensitiveData`).
- Google Translate: API key no header `X-Goog-Api-Key` (não na query string).
- Custom HTTP: `jsonEscape` completo; warning ao enviar credenciais sobre HTTP não-local.
- Cache LRU: TTL 5 min, limite 512 chars, clear ao perder foco; toggle para desligar cache.
- Clipboard backup: só tipos de texto, timeout 60 s, wipe após restore.

## [1.0.13] - 2026-08-19

Correção: ⌃⌥T no Discord — chat no painel, compose in-place, sem depender do cursor.

### Fixed

- Painel vs colar segue só `capture.isEditable` (foco AX + contexto do erro na captura) — removida heurística de banda inferior / posição do rato.
- Sempre tenta ⌘C na seleção existente antes de ⌘A+⌘C; highlight no chat abre painel Copiar only.
- Compose Electron (`noFocusedElement`): ⌘A+⌘C automático quando não há seleção visível — traduz e substitui in-place.
- `TranslationActionPolicy` centralizado; testes unitários actualizados.

## [1.0.12] - 2026-08-19

Correção: ⌃⌥T numa mensagem Discord só-leitura já não cola no compose.

### Fixed

- Highlight de mensagem no chat Discord (meio da janela) com ⌃⌥T abre painel Copiar only — o compose deixa de ser alterado.
- Decisão painel vs colar centralizada em `TranslationActionPolicy`; par de idiomas (`usedOutgoingPair`) deixa de influenciar onde colar.
- Captura editável sem seleção AX tenta ⌘C na seleção existente antes de ⌘A+⌘C (evita select-all no compose quando o highlight está no chat).
- Clipboard `.noSelectionInReadOnly` usa banda inferior da janela em vez de “elemento focado existe”.

## [1.0.11] - 2026-08-19

Correções no tutorial de primeira abertura e menos prompts assustadores de permissão.

### Fixed

- Tutorial (onboarding) abre de forma fiável na 1.ª execução e pelo botão **Ajuda** no menu bar — o painel passa a ser apresentado antes de fechar o MenuBarExtra.
- Removidos prompts automáticos duplicados no arranque (Acessibilidade + Monitoramento de Entrada + interceptor de teclado).
- No tutorial, cada permissão regista-se uma vez ao chegar ao passo; **Abrir Ajustes do Sistema** só abre Ajustes (sem segundo diálogo em cima).

## [1.0.10] - 2026-08-19

Correções de tradução em apps Electron (Discord) e select-all nos atalhos Traduzir e Painel.

### Fixed

- ⌃⌥T no compose Discord (e similares) substitui in-place em vez de abrir painel só Copiar — heurística de banda inferior do compose + par de escrita.
- ⌃⌥T e ⌃⌥Y em campo editável sem seleção fazem ⌘A+⌘C automático (TextEdit, compose Discord, Mail WebArea).
- ⌃⌥Y partilha select-all com Traduzir (`allowSelectAllWhenEditable`) sem activar colagem directa no chat.
- Substituição abortada se a tradução vier vazia (evita apagar o campo).

## [1.0.9] - 2026-08-19

Revert das janelas SwiftUI `Window` — incompatíveis com painel flutuante de menu bar.

### Fixed

- Popup/HUD voltam a `NSPanel` + `GlassPanelChrome` (Liquid Glass ou `NSVisualEffectView`) — corrige bolha invisível e janelas vazias na Dock.
- ⌃⌥T em campo editável com ⌘A implícito (`didSelectAll`) substitui directo em vez de abrir popup.
- Removido experimento `FloatingWindows` / cenas `Window`.

## [1.0.8] - 2026-08-19

Toda a UI flutuante passa a ser SwiftUI (`Window` scenes) — sem `NSPanel` / `NSHostingView`.

### Changed

- Popup de tradução, HUD, onboarding e host Apple Translation migrados para cenas `Window` com `.glassEffect()` via `GlassSurface`.
- Removidos `TranslationResultPanelController`, `StatusHUDController`, `OnboardingWindowController` e `TranslationHostPanelController`.
- Novo `FloatingWindows` centraliza estado e `openWindow` / `dismissWindow`.

## [1.0.7] - 2026-08-19

Painéis flutuantes passam a usar só SwiftUI para o visual (Liquid Glass / material).

### Changed

- Popup de tradução, HUD de status e onboarding deixam de usar `NSGlassEffectView` / `NSVisualEffectView` no AppKit; o chrome vem de `GlassSurface` (`.glassEffect()` no Tahoe, material nos demais casos).
- Removidos `GlassPanelChrome` e a flag `preferMaterialOverGlass`.

## [1.0.6] - 2026-08-19

Correção visual do painel de tradução em builds Homebrew / CI (sem SDK macOS 26).

### Fixed

- Popup de resultado (e HUD de status / onboarding) voltam a exibir a «bolha» de fundo quando o binário é compilado sem `PRISM_MACOS26_SDK`: fallback com `NSVisualEffectView` em vez de janela borderless transparente só com texto.

## [1.0.5] - 2026-08-19

Correção ao traduzir texto selecionado em apps Electron (Discord, etc.).

### Fixed

- Seleção em mensagens de chat deixava de ser tratada como só leitura quando a Acessibilidade não expõe o elemento focado: o atalho Traduzir colava no campo de composição em vez de abrir o painel com o par «texto que você lê».

## [1.0.4] - 2026-08-19

Correção de build no CI — sem mudança visível para quem já usa o app no macOS 26.

### Fixed

- APIs Liquid Glass protegidas com `PRISM_MACOS26_SDK` (`SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=macos26*]`) para compilar com Xcode 16 / SDK macOS 15 no GitHub Actions.

## [1.0.3] - 2026-08-19

Higiene de repositório e empacotamento — sem mudança de funcionalidade para quem já usa o app.

### Novidades

- Versão e build do app passam a vir só do Xcode (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`), evitando drift com o `Info.plist`.

### Fixed

- `DEVELOPMENT_TEAM` removido do projeto versionado; cada mantenedor usa `Secrets.xcconfig` local (modelo em `Secrets.xcconfig.example`).
- `RELEASING.md` e `scripts/release.sh` deixam de ser rastreados no git (mantidos só localmente).

## [1.0.2] - 2026-08-19

Ajustes de localização, acessibilidade e documentação antes do primeiro lançamento público. A `1.0.1` não foi publicada. Pacote v1 completo: todos os provedores do aceite validados de ponta a ponta.

### Novidades

- Instalação pelo Homebrew (`brew tap goobinexe/tap`, `brew trust --tap goobinexe/tap`, `brew install --cask prism-translate`). Tutorial passo a passo em `INSTALL.md`.
- Onboarding e textos da interface seguem o idioma do sistema com mais consistência, inclusive para leitores de ecrã.
- **Google Cloud Translation** e **HTTP personalizado** validados no fluxo principal (atalho → traduzir → substituir), além de Apple, DeepL e LM Studio.

### Changed

- Onboarding e componentes relacionados passam a usar `LocalizedStringKey`.
- Instruções de instalação e SVGs de compatibilidade.

### Adicionado

- Target **PrismTests** no Xcode e workflow GitHub Actions que corre `xcodebuild test` em cada push/PR.
- Empacotamento Community (`scripts/package-community.sh`) e cask Homebrew (`prism-translate`).

### Notas de maturidade

- Validado E2E: **Apple Translation**, **DeepL**, **LM Studio / OpenAI local**, **Google Cloud Translation** e **Custom HTTP**.
- Critérios de aceite da v1 em `BUILDING.md`: completos.

## [1.0.0] - 2026-08-18

Primeiro lançamento público. Instale pelo DMG — **não precisa do Xcode**.

### Novidades

- Instalador no `Prism-1.0.0.dmg`: dois cliques em **Instalar Prism** copiam o app para Aplicativos e abrem o Prism. O instalador recusa macOS anterior ao 15 e não pede Xcode, Homebrew nem ferramentas de linha de comando.
- Interface em inglês (idioma-fonte) com tradução **pt-BR** via String Catalog. O app segue o idioma do sistema.
- Continua a dar para arrastar **Prism** para **Aplicativos**, se preferir não usar o .pkg.
- Compilar a partir do código no Xcode continua possível e é opcional (só para quem clona o repositório).

### Adicionado

- Pacote `.pkg` (preinstall/postinstall) dentro do DMG, gerado por `scripts/release.sh`.
- `Localizable.xcstrings` e `InfoPlist.xcstrings` (en + pt-BR).

### Notas de maturidade

- Validado E2E: **Apple Translation**, **DeepL** e **LM Studio / OpenAI local**.
- Google Cloud Translation e Custom HTTP ainda não contam até validação ponta a ponta.

## [0.7.0] - 2026-08-14

Edição Community para o primeiro lançamento público: licença PolyForm Noncommercial, sem motores de IA na nuvem. Controles no menu bar (HUD e modo popup) e pacotes Apple Translation mais confiáveis.

### Novidades

- Edição Community com código-fonte disponível para uso não comercial (PolyForm Noncommercial 1.0.0).
- Novos controles no menu da barra: aviso perto do ponteiro e modo janela.
- O painel de tradução e as Preferências convivem melhor na tela.
- A tradução da Apple escolhe idiomas com mais confiança.
- Com o Prism desligado, o teclado volta a funcionar como de costume.
- Correções ao substituir o texto e ao copiar a tradução.
- Melhorias de estabilidade e correção de bugs.

### Adicionado

- Toggle **Aviso perto do ponteiro** (HUD) e **Modo popup** no menu da barra.
- `LICENSE` e `NOTICE` (PolyForm Noncommercial 1.0.0) no repositório e no app.

### Removed

- Motores de IA na nuvem: Groq, Gemini, Mistral, DeepSeek e OpenRouter. Permanece LM Studio / OpenAI-compatible local.

### Changed

- Mapeamento e cache de idiomas/pacotes do Apple Translation (pares concretos, menos falso “não baixado”); sessão e packs usam o mesmo mapa (chinês inclusive).
- Atalhos e Enter com Prism desligado passam o evento adiante; logs mais claros.
- Cache de tradução inclui motor/modelo/endpoint.
- Google Translate v2 envia `q`/`target` no body do POST.
- Repositório GitHub: `GoobinEXE/PrismTranslate`.

### Fixed

- Substituição falha não marca sucesso nem dispara Return.
- Copiar no painel não é mais apagado pelo restore do clipboard.
- APIs mortas removidas (`openSettings`, toggles, `settingsTest`, `isLocalDefault`, `isAIEngine`).

### Notas de maturidade

- Validado E2E: **Apple Translation**, **DeepL** e **LM Studio / OpenAI local**.
- Google Cloud Translation e Custom HTTP ainda não contam até validação ponta a ponta.

## [0.6.0] - 2026-08-13

Aba **Sobre** redesenhada: identidade, app, time, história, novidades, atualizações, suporte e legal.

### Changed

- Preferências → Sobre no fluxo de um About de produto: quem é o app, quem fez, de onde veio, o que mudou, como atualizar, como pedir ajuda.
- Novidades da versão a partir do CHANGELOG; verificar atualizações no GitHub Releases.
- Suporte compacto: tutorial, reportar problema, copiar info do app e abrir Logs.
- Legal separado (copyright, marcas, repositório e releases).

### Notas de maturidade

- Validado E2E: **Apple Translation**, **tradução por IA** e **DeepL**.
- Google Cloud Translation e Custom HTTP ainda não contam até validação ponta a ponta.

## [0.5.0] - 2026-08-13

Rebrand do produto: **Prism Translate** (nome de display no macOS: **Prism**). Pré-lançamento (sem tag/release público).

### Changed

- Identidade visual e de empacotamento: novo ícone, bundle ID `com.marcelopessoa.prism`, target/scheme `Prism`.
- Projeto Xcode e artefatos de release passam a `Prism.xcodeproj` / `Prism-x.y.z.dmg`.

### Notas de maturidade

- Validado E2E: **Apple Translation**, **tradução por IA** e **DeepL**.
- Google Cloud Translation e Custom HTTP ainda não contam até validação ponta a ponta.

## [0.4.0] - 2026-08-12

**DeepL** validado de ponta a ponta (atalho → traduzir → substituir).

### Adicionado

- Provedor DeepL (API key no Keychain) como motor de tradução testado no fluxo principal.

### Notas de maturidade

- Validado E2E: **Apple Translation**, **tradução por IA** e **DeepL**.
- Google Cloud Translation e Custom HTTP ainda não contam até validação ponta a ponta.

## [0.3.0] - 2026-08-12

Tradução por **IA** validada de ponta a ponta (atalho → traduzir → substituir), além do núcleo Apple Translation.

### Adicionado

- Provedores de IA selecionáveis em Preferências (Groq, Gemini, Mistral, DeepSeek, OpenRouter, OpenAI-compatible / LM Studio), com API key no Keychain e catálogo de modelos.

### Notas de maturidade

- Validado E2E: **Apple Translation** e **tradução por IA**.
- DeepL, Google Cloud Translation e Custom HTTP ainda não contam até validação ponta a ponta.

## [0.2.0] - 2026-08-12

Núcleo útil do app de menu bar: fluxo principal com **Apple Translation** validado de ponta a ponta (atalho → traduzir → substituir). Pré-lançamento (sem tag/release público).

### Adicionado

- Fluxo **traduzir e substituir** / **traduzir e enviar** via atalhos globais, com motor padrão Apple Translation (on-device).
- Menu bar com feedback de status, idioma destino e preferências.
- Onboarding de permissões (Acessibilidade e Monitoramento de Entrada).
- Preferências: provedor, atalhos configuráveis, abrir no login, chaves de API no Keychain.
- HUD / painel de resultado e melhorias de settings / deep-linking.

## [0.1.0] - 2026-08-05

Primeira fatia / scaffolding do QuickTranslate (menu bar, providers, hotkeys).
