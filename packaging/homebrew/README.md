# Homebrew — Prism Translate

Distribuição Community via **Homebrew Cask** (sem Apple Developer Program).

## Instalação (usuário final)

Um bloco (o Homebrew 6 exige `tap` + `trust` em repositórios não oficiais):

```bash
brew tap goobinexe/tap
brew trust --tap goobinexe/tap
brew install --cask prism-translate
```

Quando o cask entrar no [homebrew-cask](https://github.com/Homebrew/homebrew-cask) oficial, o comando ficará:

```bash
brew install --cask prism-translate
```

## Repositório do tap

O Homebrew exige um repositório separado com nome `homebrew-*`:

1. Crie **`GoobinEXE/homebrew-tap`** no GitHub (público).
2. Copie [`Casks/prism-translate.rb`](Casks/prism-translate.rb) para `Casks/prism-translate.rb` na raiz desse repo.
3. Commit e push.

Estrutura mínima do tap:

```
homebrew-tap/
  Casks/
    prism-translate.rb
  README.md          # copie tap-README.md
```

## Publicar uma nova versão

1. Rode `./scripts/package-community.sh` na raiz do PrismTranslate.
2. Anexe `build/Prism-x.y.z.zip` num GitHub Release com tag `vx.y.z`.
3. Atualize `version` e `sha256` no cask.
4. Push no `homebrew-tap`.

Validar localmente antes de publicar:

```bash
brew install --cask ./packaging/homebrew/Casks/prism-translate.rb
```

## Nome do cask

Usamos **`prism-translate`** porque `prism` já é o GraphPad Prism no homebrew-cask.
