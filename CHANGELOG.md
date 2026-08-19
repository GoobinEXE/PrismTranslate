# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o versionamento segue o [Semantic Versioning](https://semver.org/lang/pt-BR/).
A seção **Novidades** é o texto da aba Sobre (linguagem para o público). Detalhes técnicos ficam nas seções seguintes.

## [1.0.2] - 2026-08-19

Ajustes de localização, acessibilidade e documentação antes do primeiro lançamento público. A `1.0.1` não foi publicada. Pacote v1 completo: todos os provedores do aceite validados de ponta a ponta.

### Novidades

- Instalação pelo Homebrew: `brew install --cask goobinexe/tap/prism-translate`. Tutorial passo a passo em `INSTALL.md`.
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
