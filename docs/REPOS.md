# Repositórios — Prisma Tradutor

Este checkout é a **fonte da verdade** (repo privado). O GitHub público recebe apenas
exportações Community filtradas.

## URLs

| Repo | Visibilidade | Remote local | Uso |
|------|--------------|--------------|-----|
| [GoobinEXE/Prisma-Tradutor](https://github.com/GoobinEXE/Prisma-Tradutor) | **Privado** | `origin` | Desenvolvimento diário, push normal |
| [GoobinEXE/PrismTranslate](https://github.com/GoobinEXE/PrismTranslate) | Público (Community) | `community` | Só via `./scripts/publish-community.sh` |

## Primeira vez (criar repo privado)

Se `git push origin main` falhar com *Repository not found*:

```bash
gh auth login
./scripts/bootstrap-private-repo.sh
```

Ou manualmente:

```bash
gh repo create GoobinEXE/Prisma-Tradutor --private \
  --description "Prisma Tradutor — fonte completa (mantenedor)"
git push -u origin main
git push origin --tags
```

## Fluxo diário

```bash
# Trabalho normal — repo privado
git add …
git commit -m "…"
git push origin main
```

## Publicar Community (público)

**Nunca** `git push community main` a partir do branch privado sem filtrar.

```bash
./scripts/publish-community.sh
# opcional: ./scripts/publish-community.sh --tag v1.0.4
./scripts/package-community.sh
```

O script:

1. Clona/atualiza `.community-publish/PrismTranslate` a partir de `community`
2. `rsync` da árvore local excluindo [`scripts/community-excludes.txt`](../scripts/community-excludes.txt)
3. Aplica [`.gitignore` Community](../scripts/community-gitignore) no clone
4. Commit + push para `GoobinEXE/PrismTranslate`

Pré-visualizar alterações: `./scripts/publish-community.sh --dry-run`

## Só no privado (nunca no público)

Definido em `scripts/community-excludes.txt`:

- Documentação de mantenedor: `AGENTS.md`, `BUILDING.md`, `RELEASING.md`, `VERSIONING.md`, `docs/REPOS.md`
- Scripts: `release.sh`, `gen_xcstrings.py`, `publish-community.sh`
- IDE/agentes: `.cursor/`, `.vscode/`, `buildServer.json`
- Brand interno: `docs/brand/`
- Homebrew maintainer docs em `packaging/homebrew/README.md`
- **Futuro:** `PrismPro/` (IAP, StoreKit, motores cloud)

## Só local (nunca em nenhum remote)

- `Secrets.xcconfig`, chaves, `.env`, credenciais

## Remotes

```bash
git remote -v
# origin    https://github.com/GoobinEXE/Prisma-Tradutor.git
# community https://github.com/GoobinEXE/PrismTranslate.git
```

Se `origin` ainda apontar para o público, renomeie:

```bash
git remote rename origin community
git remote add origin https://github.com/GoobinEXE/Prisma-Tradutor.git
```
