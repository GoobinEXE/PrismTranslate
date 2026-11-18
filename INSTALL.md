# Como instalar o Prism Translate

Tutorial para quem nunca usou o Terminal ou o Homebrew. O Prism funciona no **macOS 15 (Sequoia) ou mais novo**.

## Resumo rápido

Se você **já tem o Homebrew**, cole estes três comandos:

```bash
brew tap goobinexe/tap
brew trust --tap goobinexe/tap
brew install --cask prism-translate
```

O `trust` é necessário porque o Prism ainda não está no catálogo oficial do Homebrew. Depois abra **Prism** em Aplicativos e autorize as permissões (seção 4).

**Sem Homebrew:** baixe `Prism-x.y.z.dmg` em [GitHub Releases](https://github.com/GoobinEXE/PrismTranslate/releases/latest), abra o arquivo e arraste o Prism para Aplicativos (veja [Alternativa sem Homebrew](#alternativa-sem-homebrew)).

---

## 1. Instalar o Homebrew (só na primeira vez)

O Homebrew é um instalador de programas para Mac usado por milhões de pessoas. Você só precisa fazer isto uma vez no computador.

1. Abra o **Terminal** (Spotlight: ⌘Espaço, digite *Terminal*, Enter).
2. Cole este comando e pressione Enter:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

3. O instalador pode pedir a **senha do Mac** (a que você usa para entrar). Ao digitar, **nada aparece na tela** — é normal. Pressione Enter depois.
4. Siga as mensagens na tela. No fim, se aparecer um comando `echo 'eval ...'` para colar, copie e rode (o instalador mostra exatamente o que colar).

Site oficial: [brew.sh](https://brew.sh)

---

## 2. Instalar o Prism

No Terminal, cole estes três comandos (um de cada vez, Enter após cada um):

```bash
brew tap goobinexe/tap
brew trust --tap goobinexe/tap
brew install --cask prism-translate
```

O Homebrew baixa o Prism, copia para **Aplicativos** e remove o aviso de quarentena do download.

**Por que `--cask`?** Programas com janela ou ícone na barra de menus (como o Prism) são instalados como *cask*. O comando `brew install` sozinho é para ferramentas de linha de comando.

**Por que `tap` e `trust`?** Enquanto o Prism não entra no catálogo oficial, ele vive num repositório extra do autor. O Homebrew 6 só instala desse repositório depois que você o marca como confiável. No futuro bastará `brew install --cask prism-translate`.

---

## 3. Primeira abertura (aviso do macOS)

A partir da versão 1.1.1, o Prism instalado pelo Homebrew é assinado com Developer ID e notarizado pela Apple. Na primeira abertura o macOS mostra só o aviso de app baixado da internet; clique em **Abrir**.

Se você compilou o Prism a partir do código ou usa uma versão anterior à 1.1.1, o macOS pode dizer que o app **não foi verificado**:

1. Abra **Aplicativos** e dê dois cliques em **Prism**.
2. Se aparecer que não pode abrir, vá em **Ajustes do Sistema → Privacidade e Segurança**.
3. Role até o final e clique em **Abrir Mesmo Assim**.
4. Confirme **Abrir**.

---

## 4. Permissões obrigatórias

O Prism precisa de duas permissões para ler o texto do campo e reagir aos atalhos:

| Permissão | Para quê |
|-----------|----------|
| **Acessibilidade** | Ler e substituir o texto no campo focado |
| **Monitoramento de Entrada** | Atalhos globais (⌃⌥T e ⌃⌥⏎) em qualquer app |

**Onde ligar:** Ajustes do Sistema → Privacidade e Segurança → **Acessibilidade** e **Monitoramento de Entrada** → marque **Prism**.

Na primeira execução, o tutorial do app tem 4 passos: boas-vindas com os atalhos, as duas permissões na mesma tela, idioma e tradução, e um resumo final. Dá para seguir sem conceder as permissões (**Continuar mesmo assim**), mas os atalhos só funcionam depois delas. Para reabrir o tutorial, use **Guia de configuração** no menu do prisma. Se algo não funcionar, **feche e abra o Prism** de novo depois de marcar as caixas.

Pacotes de idioma da tradução da Apple, se faltarem, o próprio app baixa.

---

## 5. Usar

Com o ícone do prisma na barra de menus (canto superior direito):

| Atalho | Ação |
|--------|------|
| **⌃⌥T** (Control + Option + T) | Traduz o texto selecionado ou do campo, no lugar; em texto só de leitura, abre o painel de tradução |
| **⌃⌥⏎** (Control + Option + Enter) | Traduz e simula Enter (enviar) |
| **⌃⌥Y** | Abre o painel de tradução (só com **Modo popup** ligado) |

Dá para mudar os atalhos em **Configurações → Atalhos**.

---

## Alternativa sem Homebrew

1. Abra a [versão mais recente no GitHub Releases](https://github.com/GoobinEXE/PrismTranslate/releases/latest).
2. Em **Assets**, baixe `Prism-x.y.z.dmg`.
3. Dê dois cliques no DMG. Na janela que abre, arraste **Prism** para o atalho **Aplicativos**.
4. Ejete o disco "Prism Translate" no Finder.
5. Abra **Prism** em Aplicativos e siga as seções **3** (aviso do macOS) e **4** (permissões) deste guia.

O `Prism-x.y.z.zip` do mesmo release tem o mesmo app: descompacte e arraste para Aplicativos. O DMG e o zip são assinados com Developer ID e notarizados pela Apple a partir da 1.1.1.

Sem Homebrew, o Prism não se atualiza sozinho: repita estes passos a cada versão nova.

---

## Atualizar

```bash
brew upgrade --cask prism-translate
```

---

## Desinstalar

### Instalado pelo Homebrew

```bash
brew uninstall --cask prism-translate
```

Para remover também preferências e dados locais:

```bash
brew uninstall --cask --zap prism-translate
```

O `--zap` apaga `~/Library/Preferences/dev.prism.tradutor.plist` (e o plist legado `com.marcelopessoa.prism`) e `~/Library/Application Support/Prism`.

### Instalado manualmente (DMG ou zip)

1. Feche o Prism com **Sair**, no rodapé do menu da barra de menus (**Ligado** só pausa o app).
2. Arraste **Prism** de **Aplicativos** para o Lixo.
3. Esvazie o Lixo.

### Limpar permissões e chaves (opcional)

- **Ajustes do Sistema → Privacidade e Segurança:** remova **Prism** de **Acessibilidade** e **Monitoramento de Entrada**.
- **Chaveiro:** abra o app **Acesso às Chaves**, busque por `dev.prism.tradutor` (e, se existir, `com.marcelopessoa.prism`) e apague entradas de API se não for reinstalar.

Se não usou `--zap`, pode apagar manualmente (Finder → **Ir → Ir para a pasta…**, ⌘⇧G):

- `~/Library/Preferences/dev.prism.tradutor.plist`
- `~/Library/Application Support/Prism`

---

## Problemas comuns

**“command not found: brew”**  
O Homebrew não foi instalado ou o Terminal não carregou o PATH. Repita a seção 1 e o comando `eval` que o instalador mostra no fim.

**“Refusing to load cask … from untrusted tap”**  
Rode `brew trust --tap goobinexe/tap` e depois `brew install --cask prism-translate` de novo.

**Atalhos não funcionam**  
Confira Monitoramento de Entrada e Acessibilidade. Reinicie o Prism.

**Tradução não aparece**  
Confirme macOS 15+, permissões ok e idioma de destino no menu do prisma.

**Quero compilar o código**  
Opcional — clone o repositório, abra `Prism.xcodeproj` no Xcode 16+ (macOS 15+) e rode o target **Prism**.
