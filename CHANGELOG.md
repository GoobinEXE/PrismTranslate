# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e o versionamento segue o [Semantic Versioning](https://semver.org/lang/pt-BR/).

## [0.1.0] - AAAA-MM-DD

Primeira versão pública do QuickTranslate — app de menu bar para macOS que traduz o texto do campo focado via atalhos globais.

### Adicionado

- **Traduzir e substituir** o texto do campo focado com `⌃⌥T` (sem enviar).
- **Traduzir e enviar** com `⌃⌥⏎` (substitui o texto e simula Enter).
- **Modo Enter** opcional: com “Enter traduz e envia” ligado, a própria tecla Enter traduz antes de enviar.
- **5 provedores de tradução** selecionáveis em Preferências:
  - Apple Translation (on-device, padrão, zero configuração)
  - DeepL (API key)
  - Google Cloud Translation (API key)
  - OpenAI-compatible / LM Studio (base URL + modelo; key opcional)
  - Custom HTTP (URL, template JSON e path da resposta configuráveis)
- **Atalhos configuráveis** em Preferências → Atalhos, com botão para restaurar os padrões `⌃⌥T` / `⌃⌥⏎`.
- **Chaves de API no Keychain** — nenhuma credencial fica em texto plano.
- **Abrir no login** — toggle em Preferências registra o app como login item.
- **Onboarding** guiado na primeira execução, com passos para conceder as permissões de Acessibilidade e Monitoramento de Entrada.
- **Feedback visual no ícone** da barra de menus (idle, traduzindo, sucesso, erro).
