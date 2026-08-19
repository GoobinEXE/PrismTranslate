---
name: version-judgment
description: >
  Judges the correct MAJOR.MINOR.PATCH product version from real maturity
  (what works and was tested end-to-end), using git history, tags, releases,
  README/acceptance criteria, and user context — not the number already written
  in Info.plist, package.json, or MARKETING_VERSION. Use when the user asks to
  define, judge, choose, bump, or update the version; asks “qual versão estamos?”;
  wants a version recommendation before release; OR when the agent implements a
  bugfix / fix in product code (then bump PATCH as part of the same work).
  Prefer analysis-only for judgment questions; apply the bump when implementing
  a fix after a public release exists, or when the user explicitly asks.
---

# Version judgment (maturidade real)

Modo padrão para **perguntas** de versão: **análise** — investigar e julgar; não editar arquivos só para “adivinhar” a versão.

**Exceção — fix no código:** depois que existir release público (`v1.0.0`+ / GitHub Release), **toda correção de bug ou fix no código já inclui o bump PATCH** (plist, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `CHANGELOG.md`, baseline em `VERSIONING.md` se existir). Não esperar o usuário pedir “bumpa”. Tag/GitHub Release continuam **só com pedido explícito**.

Se o repo tiver `VERSIONING.md` (ou equivalente), leia a seção **Baseline** primeiro; contexto do usuário (“só X funciona”) tem **prioridade** sobre código e sobre o baseline se divergirem.

Responda em **português**, de forma direta.

## Esquema (obrigatório)

Formato: `MAJOR.MINOR.PATCH` — **sempre três componentes**. Nunca publique `1.1` no lugar de `1.1.0` / `1.1.1`.

- **MAJOR** = lançamento / relançamento / atualização gigante (quebra grande, produto “novo”, ou primeiro release público)
- **MINOR** = melhoria grande (feature nova relevante, provedor novo, fluxo principal novo)
- **PATCH** = melhoria pequena (bugfix, polish, ajuste fino)

### PATCH e MINOR+fix (`x.y.1`)

Sempre que o trabalho incluir correção de bug, fix ou polish:

| Trabalho | Versão |
|----------|--------|
| Só bugfix / fix / polish | Incrementa PATCH: `1.0.0` → `1.0.1` → `1.0.2` (depois do 9 vem `10`) |
| Feature nova (MINOR) **e** também tem fix no mesmo bump | MINOR+1 e **PATCH = 1**: `1.0.2` → `1.1.1` — **nunca** `x.y.0` se o release contém correção |
| Só feature, zero fix | MINOR+1 e PATCH = 0: `1.1.0` |
| Primeiro lançamento ainda sem tag pública | Acumula no `1.0.0` corrente (não inventar `1.0.1` antes do `v1.0.0`) |

Exemplos: `1.0.0` + fix → `1.0.1`; `1.0.1` + feature e fix → `1.1.1`; `1.1.1` + só feature → `1.2.0`.

Regras:

1. Ignore o número atual em Info.plist / package.json / MARKETING_VERSION / tags locais se ele não reflete a realidade.
2. Se NUNCA houve lançamento público (sem tag de release, sem GitHub Release, sem artefato publicado), MAJOR permanece 0 (pré-1.0) — salvo o baseline do repo já ter decidido `1.0.0` pendente de tag.
3. O primeiro lançamento público confiável sobe para 1.0.0 — não invente 1.x antes disso.
4. Julgue pelo que FUNCIONA e foi TESTADO de ponta a ponta, não pelo que só existe no código/UI/docs.
5. Código/UI para features incompletas, stubs, providers não validados ou “parece pronto mas não está” NÃO contam como MINOR concluído.
6. Não invente histórico fictício de versões (0.2, 0.3…) só para “preencher buracos”, a menos que o git/tags/changelog mostrem releases reais.
7. **Componentes são inteiros, não dígitos 0–9.** Depois do `9` o próximo MINOR/PATCH é `10`, `11`, … — **não** obriga subir de faixa nem o MAJOR. Exemplos válidos: `0.10.0`, `0.11.2`, `1.10.0`. Nunca trate `0.9` → `1.0` só porque o MINOR passou de 9.

## Investigar (antes de concluir)

### A) Git / histórico

- `git tag -l --sort=-v:refname` e releases (`gh release list` se houver)
- `git log --oneline --decorate` (e com datas se útil)
- `git describe --tags --always`
- Diffs agregados se necessário: `git log --stat`, `git diff <primeiro-commit>..HEAD --stat`
- Branches/remote só se relevantes para “já foi publicado?”

### B) Evidência de lançamento

- Tags `v*`, GitHub Releases, CHANGELOG com datas reais, scripts de release, artefatos (DMG/IPA/npm publish), docs tipo RELEASING.md
- Sem release público → não lançado (MAJOR = 0), salvo baseline explícito pendente de tag

### C) Escopo prometido vs real

- README / critérios de aceite / roadmap / changelog
- O que o produto AFIRMA oferecer → para cada item: implementado? testado E2E? ou só scaffold/UI?

### D) Maturidade funcional (prioridade máxima)

- Fluxo principal comprovadamente funcionando?
- Partes existentes mas NÃO testadas / não aplicadas funcionalmente?
- Dependências externas (APIs, providers) só “ligadas” na UI?

## Mapear maturidade → número

Pré-release (MAJOR = 0 se não lançado) — faixas **orientativas** (MINOR pode ir além de 9):

- `0.1.x` = esqueleto / primeira fatia mínima validada
- `0.2.x`–`0.4.x` = núcleo útil funciona; várias partes prometidas ainda incompletas/não testadas
- `0.5.x`–`0.8.x` = maior parte do escopo v1 validada; faltam poucos itens
- `0.9.x`+ (inclui `0.10.x`, `0.11.x`, …) = perto do feature-complete da v1 / faltam poucos itens ou só aceite + release — **sem** forçar `1.0.0` só pelo número
- `1.0.0` = primeiro lançamento público do pacote mínimo confiável (decisão de maturidade/publicação, não “estourou o 9”)

Após `1.0.0`: PATCH = fixes/polish (`1.0.1`, `1.0.2`…); MINOR = feature grande compatível (`1.1.0`, ou `1.1.1` se o mesmo bump incluir fix); MAJOR = relançamento / mudança gigante / incompatibilidade grande.

## Formato da resposta

1. **Veredito:** versão recomendada (ex.: `0.2.0` ou `1.0.1`) + uma linha de porquê
2. **Lançado?** sim/não + evidência git (tags/releases/changelog)
3. **O que conta como pronto** (só o validado/funcional)
4. **O que NÃO conta** (código/UI sem validação)
5. **Próximos bumps sugeridos**
6. **O que mudar no projeto** (orientação: onde bumpa + changelog) — sem editar nada no modo análise, **exceto** quando esta skill aplicar bump de PATCH por um fix

Se faltar informação crítica, diga a hipótese e faça 1–3 perguntas objetivas.

## Ao aplicar bump

Localize os arquivos de versão do projeto (comum: `package.json`, `Info.plist`, `MARKETING_VERSION` no `.pbxproj`, `CHANGELOG.md`). Atualize o baseline em `VERSIONING.md` se existir. Não invente tags/releases sem pedido.

Aplicar **sem** o usuário pedir “bumpa” quando: o agente acabou de implementar um bugfix/fix **e** já existe release público. Caso contrário, só com pedido explícito.
