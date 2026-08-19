# Julgamento de versão (maturidade real)

Baseline **específico deste repo**. O fluxo completo está na skill **`version-judgment`**
(`~/.cursor/skills/version-judgment/` e `.cursor/skills/version-judgment/`).

Quando pedir para definir/julgar versão: o agente deve **ler a skill** e usar este
baseline como ponto de partida (contexto do usuário prevalece se divergir).

## Baseline atual (atualize quando a realidade mudar)

- **Versão justa agora:** `1.0.4` (fix de compilação CI com SDK anterior ao macOS 26)
- **Distribuição:** Homebrew Cask (`goobinexe/tap/prism-translate`) + zip no GitHub Releases — sem Apple Developer Program por agora
- **Lançado?** Sim — tag `v1.0.3` no GitHub (próximo patch `1.0.4` pendente de tag); zip e cask a publicar manualmente após tag
- **Futuro:** DMG notarizado via Developer ID (`scripts/release.sh`)
- **Validado E2E:** Apple Translation, DeepL, LM Studio / OpenAI local, **Google Cloud Translation** e **Custom HTTP** (atalho → traduzir → substituir)
- **Identidade:** rebrand **Prism Translate** (display **Prism**; bundle `com.marcelopessoa.prism`)
- **Aceite v1:** checklist de `BUILDING.md` completo (confirmado pelo autor)

## Notas deste repo

- SemVer com inteiros: depois de `0.9.x` pode vir `0.10.x` (não obriga `1.0.0` só por passar do 9).
- `1.0.0` aqui é decisão de publicação (DMG para quem não tem Xcode), não “estourou o 9”.
- Sempre três componentes `MAJOR.MINOR.PATCH`.
- **Fix / bugfix:** incrementa PATCH (`1.0.0` → `1.0.1`). Depois de existir release público, o agente aplica esse bump junto com o fix (sem esperar “bumpa”).
- **MINOR + fix no mesmo bump:** `x.y.1`, nunca `x.y.0` (ex.: `1.0.2` + feature e correção → `1.1.1`).
- **Só feature, zero fix:** `x.y.0` (ex.: `1.1.0`).
- Tag/GitHub Release só com pedido explícito.

## Onde bumpa neste projeto (PATCH de fix após release público, ou com pedido explícito)

- `Prism.xcodeproj/project.pbxproj` → `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
- `Prism/Info.plist` → `CFBundleShortVersionString` / `CFBundleVersion`
- `CHANGELOG.md` → entrada com data real e escopo honesto
- Release público Community: tag `vX.Y.Z` + GitHub Release + zip (`scripts/package-community.sh` / `RELEASING.md` §0)
- Release oficial futuro: DMG (`scripts/release.sh` / `RELEASING.md` §A)
- Depois do bump: atualizar a seção Baseline acima
