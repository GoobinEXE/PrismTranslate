# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o versionamento segue o [Semantic Versioning](https://semver.org/lang/pt-BR/).

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
