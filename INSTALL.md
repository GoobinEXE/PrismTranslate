# Como instalar o Prism Translate

Tutorial para quem nunca usou o Terminal ou o Homebrew. O Prism funciona no **macOS 15 (Sequoia) ou mais novo**.

## Resumo rápido

Se você **já tem o Homebrew**:

```bash
brew install --cask goobinexe/tap/prism-translate
```

Depois abra **Prism** em Aplicativos e autorize as permissões (seção 4).

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

No Terminal, cole e pressione Enter:

```bash
brew install --cask goobinexe/tap/prism-translate
```

O Homebrew baixa o Prism, copia para **Aplicativos** e remove o aviso de quarentena do download.

**Por que `--cask`?** Programas com janela ou ícone na barra de menus (como o Prism) são instalados como *cask*. O comando `brew install` sozinho é para ferramentas de linha de comando.

**Por que `goobinexe/tap/`?** Enquanto o Prism não entra no catálogo oficial do Homebrew, o app fica num *tap* (repositório extra) do autor. É um prefixo temporário — no futuro bastará `brew install --cask prism-translate`.

---

## 3. Primeira abertura (aviso do macOS)

Como o Prism ainda não usa certificado pago da Apple (Developer ID), o macOS pode mostrar que o app **não foi verificado**:

1. Abra **Aplicativos** e dê dois cliques em **Prism**.
2. Se aparecer que não pode abrir, vá em **Ajustes do Sistema → Privacidade e Segurança**.
3. Role até o final e clique em **Abrir Mesmo Assim**.
4. Confirme **Abrir**.

Isso é esperado na edição Community. Um instalador DMG assinado pode vir numa versão futura.

---

## 4. Permissões obrigatórias

O Prism precisa de duas permissões para ler o texto do campo e reagir aos atalhos:

| Permissão | Para quê |
|-----------|----------|
| **Acessibilidade** | Ler e substituir o texto no campo focado |
| **Monitoramento de Entrada** | Atalhos globais (⌃⌥T e ⌃⌥⏎) em qualquer app |

**Onde ligar:** Ajustes do Sistema → Privacidade e Segurança → **Acessibilidade** e **Monitoramento de Entrada** → marque **Prism**.

O onboarding do app guia na primeira execução. Se algo não funcionar, **feche e abra o Prism** de novo depois de marcar as caixas.

Pacotes de idioma da tradução da Apple, se faltarem, o próprio app baixa.

---

## 5. Usar

Com o ícone do prisma na barra de menus (canto superior direito):

| Atalho | Ação |
|--------|------|
| **⌃⌥T** (Control + Option + T) | Traduz o texto selecionado ou do campo, no lugar |
| **⌃⌥⏎** (Control + Option + Enter) | Traduz e simula Enter (enviar) |

Dá para mudar os atalhos em **Preferências → Atalhos**.

---

## Alternativa sem Homebrew

1. Abra [GitHub Releases](https://github.com/GoobinEXE/PrismTranslate/releases).
2. Baixe o arquivo `Prism-x.y.z.zip` da versão mais recente.
3. Dê dois cliques no zip para descompactar.
4. Arraste **Prism** para a pasta **Aplicativos**.
5. Siga as seções **3** (aviso do macOS) e **4** (permissões) deste guia.

---

## Atualizar

```bash
brew upgrade --cask prism-translate
```

Se instalou pelo tap `goobinexe/tap`:

```bash
brew upgrade --cask goobinexe/tap/prism-translate
```

---

## Desinstalar

```bash
brew uninstall --cask prism-translate
```

Remova também as entradas de **Prism** em Acessibilidade e Monitoramento de Entrada se quiser limpar tudo.

---

## Problemas comuns

**“command not found: brew”**  
O Homebrew não foi instalado ou o Terminal não carregou o PATH. Repita a seção 1 e o comando `eval` que o instalador mostra no fim.

**Atalhos não funcionam**  
Confira Monitoramento de Entrada e Acessibilidade. Reinicie o Prism.

**Tradução não aparece**  
Confirme macOS 15+, permissões ok e idioma de destino no menu do prisma.

**Quero compilar o código**  
Opcional — só para desenvolvedores. Veja [BUILDING.md](BUILDING.md).

---

## Para mantenedores

- Empacotar zip: `./scripts/package-community.sh`
- Cask: [`packaging/homebrew/`](packaging/homebrew/)
- Release oficial futuro (DMG + Developer ID): [RELEASING.md](RELEASING.md)
