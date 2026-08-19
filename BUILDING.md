# Compilar e desenvolver o Prism

Este arquivo é **opcional**. Só precisa dele quem clona o repositório para estudar ou mudar o código.

Quem só quer usar o Prism **não instala o Xcode**: baixa o `.dmg` em [GitHub Releases](../../releases), corre o instalador e pronto. O [README](README.md) descreve esse caminho. Publicar o DMG oficial (assinatura Apple, notarização, GitHub Release) está em [`RELEASING.md`](RELEASING.md), só para quem corta a build pública.

Esta é a edição **Community**. O código é para uso não comercial. Trabalho comercial ou freemium não entra neste repo.

## O que você precisa

- macOS 15.0+ (Sequoia) — a tradução da Apple depende disso
- Xcode 16+
- Permissões de **Acessibilidade** e **Monitoramento de Entrada** (o onboarding pede na primeira execução)

## Abrir e rodar

1. Abra `Prism.xcodeproj` no Xcode
2. Selecione o target **Prism** e rode (⌘R)
3. Autorize Acessibilidade (e Monitoramento de Entrada, se o sistema pedir)
4. O ícone do prisma aparece na barra de menus

Build pela linha de comando, com o Xcode.app (não use o `xcodebuild` de `/usr/bin` se der conflito de arquitetura):

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Prism.xcodeproj \
  -scheme Prism \
  -configuration Debug \
  build
```

## Estrutura

```
Prism/
  App/           # Menu bar, estado, orquestração
  Hotkeys/       # CGEvent tap (atalhos + Enter)
  TextIO/        # Accessibility + fallback clipboard
  Translation/   # Protocolo e engine
  Providers/     # Apple, DeepL, Google, LM Studio / OpenAI local, Custom HTTP
  Settings/      # Preferências
  Design/        # Tokens visuais e glifo Prism
  Utilities/     # Teclado, Keychain, permissões
```

Atalhos padrão (`⌃⌥T` / `⌃⌥⏎`): `Prism/Hotkeys/HotkeyChord.swift` e `Prism/Settings/AppSettings.swift`.

Testes unitários: [`PrismTests/README.md`](PrismTests/README.md) (ainda precisam de um target de testes no Xcode; o README da pasta explica como criar).

## Critérios de aceite — v1.0

A v1.0 está pronta quando todos os itens abaixo funcionam de ponta a ponta:

- [ ] **Traduzir / substituir** — com o foco em um campo de texto, `⌃⌥T` lê o texto, traduz e substitui no lugar (sem enviar)
- [ ] **Traduzir + enviar** — `⌃⌥⏎` traduz, substitui e simula Enter
- [ ] **Onboarding de permissões** — na primeira execução, o tutorial guia Acessibilidade e Monitoramento de Entrada, com links para Ajustes do Sistema
- [ ] **Provedores** — Apple Translation, DeepL, Google Cloud Translation, OpenAI-compatible / LM Studio e Custom HTTP selecionáveis em Preferências
- [ ] **Atalhos configuráveis** — gravar novos atalhos e restaurar os padrões `⌃⌥T` / `⌃⌥⏎` em Preferências → Atalhos
- [ ] **Abrir no login** — o toggle em Preferências registra/desregistra o login item

## Licença para quem modifica

Prism Translate Community está sob a [PolyForm Noncommercial License 1.0.0](LICENSE).

Você pode usar, estudar e modificar o código para fins **não comerciais** (uso pessoal, pesquisa, organizações listadas na licença). Uso comercial exige uma licença à parte, concedida pelo autor. O aviso obrigatório está em [`NOTICE`](NOTICE).
