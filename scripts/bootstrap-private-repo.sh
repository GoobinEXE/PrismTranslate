#!/usr/bin/env bash
#
# bootstrap-private-repo.sh — Cria GoobinEXE/Prisma-Tradutor e faz o primeiro push.
# Requer: gh auth login (uma vez).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! gh auth status &>/dev/null; then
  echo "Erro: faça login primeiro — gh auth login" >&2
  exit 1
fi

if gh repo view GoobinEXE/Prisma-Tradutor &>/dev/null; then
  echo "Repo GoobinEXE/Prisma-Tradutor já existe."
else
  gh repo create GoobinEXE/Prisma-Tradutor --private \
    --description "Prisma Tradutor — fonte completa (mantenedor)"
fi

if ! git remote get-url origin &>/dev/null; then
  git remote add origin https://github.com/GoobinEXE/Prisma-Tradutor.git
fi

git push -u origin main
git push origin --tags 2>/dev/null || true

echo "Pronto: origin → GoobinEXE/Prisma-Tradutor (privado)"
