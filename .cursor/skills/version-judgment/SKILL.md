---
name: version-judgment
description: >
  Judges the correct MAJOR.MINOR.PATCH product version from real maturity
  (what works and was tested end-to-end), using git history, tags, releases,
  README/acceptance criteria, and user context — not the number already written
  in Info.plist, package.json, or MARKETING_VERSION. Use when the user asks to
  define, judge, choose, bump, or update the version; asks “qual versão estamos?”;
  or wants a version recommendation before release. Do NOT use for routine code
  edits unless versioning was requested. Prefer analysis-only unless the user
  explicitly asks to apply the bump.
---

# Version judgment (maturidade real)

Modo padrão: **análise** — investigar e julgar; **não editar** arquivos só para “adivinhar” a versão. Só aplique bump (plist / MARKETING_VERSION / CHANGELOG / tag) se o usuário pedir explicitamente.

Se o repo tiver `VERSIONING.md` (ou equivalente), leia a seção **Baseline** primeiro; contexto do usuário (“só X funciona”) tem **prioridade** sobre código e sobre o baseline se divergirem.

Responda em **português**, de forma direta.

## Esquema (obrigatório)

Formato: `MAJOR.MINOR.PATCH`

- **MAJOR** = lançamento / relançamento / atualização gigante (quebra grande, produto “novo”, ou primeiro release público)
- **MINOR** = melhoria grande (feature nova relevante, provedor novo, fluxo principal novo)
- **PATCH** = melhoria pequena (bugfix, polish, ajuste fino)

Regras:

1. Ignore o número atual em Info.plist / package.json / MARKETING_VERSION / tags locais se ele não reflete a realidade.
2. Se NUNCA houve lançamento público (sem tag de release, sem GitHub Release, sem artefato publicado), MAJOR permanece 0 (pré-1.0).
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
- Sem release público → não lançado (MAJOR = 0)

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

Após `1.0.0`: PATCH = fixes/polish; MINOR = feature grande compatível (pode ser `1.10.0`); MAJOR = relançamento / mudança gigante / incompatibilidade grande.

## Formato da resposta

1. **Veredito:** versão recomendada (ex.: `0.2.0`) + uma linha de porquê
2. **Lançado?** sim/não + evidência git (tags/releases/changelog)
3. **O que conta como pronto** (só o validado/funcional)
4. **O que NÃO conta** (código/UI sem validação)
5. **Próximos bumps sugeridos**
6. **O que mudar no projeto** (orientação: onde bumpa + changelog) — sem editar nada no modo análise

Se faltar informação crítica, diga a hipótese e faça 1–3 perguntas objetivas.

## Ao aplicar bump (só se pedido)

Localize os arquivos de versão do projeto (comum: `package.json`, `Info.plist`, `MARKETING_VERSION` no `.pbxproj`, `CHANGELOG.md`). Atualize o baseline em `VERSIONING.md` se existir. Não invente tags/releases sem pedido.
