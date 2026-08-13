# Julgamento de versão (maturidade real)

Baseline **específico deste repo**. O fluxo completo está na skill **`version-judgment`**
(`~/.cursor/skills/version-judgment/` e `.cursor/skills/version-judgment/`).

Quando pedir para definir/julgar versão: o agente deve **ler a skill** e usar este
baseline como ponto de partida (contexto do usuário prevalece se divergir).

## Baseline atual (atualize quando a realidade mudar)

- **Versão justa agora:** `0.6.0` (pré-lançamento; MAJOR = 0)
- **Lançado?** Não (sem tags `v*`, sem GitHub Release, sem DMG público)
- **Validado E2E:** **Apple Translation**, **tradução por IA** e **DeepL** (atalho → traduzir → substituir)
- **Identidade:** rebrand **Prism Translate** (display **Prism**; bundle `com.marcelopessoa.prism`)
- **Não conta ainda:** Google, Custom HTTP; aceite v1 do README ainda unchecked

## Notas deste repo

- SemVer com inteiros: depois de `0.9.x` pode vir `0.10.x` (não obriga `1.0.0` só por passar do 9).

## Onde bumpa neste projeto (só com pedido explícito)

- `Prism.xcodeproj/project.pbxproj` → `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
- `Prism/Info.plist` → `CFBundleShortVersionString` / `CFBundleVersion`
- `CHANGELOG.md` → entrada com data real e escopo honesto
- Release público: tag `vX.Y.Z` + GitHub Release + DMG (`scripts/release.sh` / `RELEASING.md`)
- Depois do bump: atualizar a seção Baseline acima
