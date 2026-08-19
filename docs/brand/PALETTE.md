# Paleta Prism — identidade visual

**Estado: especificada. Ainda não aplicada.**

Esta é a paleta canónica da logo e de identidades visuais futuras. Não migrar App Icon, `AccentColor`, glifo da barra de menus, `QTDesign`, SVGs do README nem artes existentes até pedido explícito.

Referência: capa de cassete VHS / synthwave (fundos quase pretos, faixas no topo, semicírculos em baixo, pixels esparsos). Estilo: minimalista, plano, grelha, muito espaço negativo.

Slogan de marca: **Um prisma. Vários idiomas.**

---

## Tokens (sRGB)

Usar **só** estas cores em logo, posters, stories, site e empacotamento. Sem arco-íris óptico (vermelho → violeta), sem ciano, sem verde-lima, sem branco puro.

| Token | Papel | Hex | RGB | SwiftUI sRGB (0–1) |
|---|---|---|---|---|
| `ink` | Fundo, superfícies escuras, traço em fundo claro | `#0A0D16` | 10 13 22 | `0.039 0.051 0.086` |
| `paper` | Texto, faixas claras, contorno do prisma | `#F3EDE0` | 243 237 224 | `0.953 0.929 0.878` |
| `magenta` | Acento primário, títulos, ênfase | `#E83A9B` | 232 58 155 | `0.910 0.227 0.608` |
| `ochre` | Acento secundário, primeira faixa do espectro | `#E0B84A` | 224 184 74 | `0.878 0.722 0.290` |
| `violet` | Geometria, terceira faixa do espectro | `#6A4A9A` | 106 74 154 | `0.416 0.290 0.604` |
| `indigo` | Geometria profunda, quarta faixa do espectro | `#2A3F8F` | 42 63 143 | `0.165 0.247 0.561` |

Nomes de marca (copy): **Prism Ink**, **Prism Paper**, **Prism Magenta**, **Prism Ochre**, **Prism Violet**, **Prism Indigo**.

---

## Espectro da marca (não é o arco-íris)

O prisma decompõe **um** feixe em **várias** línguas. O fan tem **quatro** faixas, nesta ordem, de dentro para fora / do feixe para o espalhamento:

1. `ochre`
2. `magenta`
3. `violet`
4. `indigo`

Nunca as sete bandas ópticas (vermelho, laranja, amarelo, verde, ciano, azul, violeta). Isso é a identidade antiga do ícone de vidro.

---

## Logo (quando for desenhada)

- Prisma **geométrico 2D** (triângulo / prisma óptico em traço), não vidro fotorealista, não render 3D.
- Fundo preferido: `ink`.
- Contorno e feixe de entrada: `paper`.
- Fan de saída: as quatro faixas do espectro, planas, sem glow.
- Versão monocromática (barra de menus, template): continua a ser traço único — o glifo actual em `PrismGlyph` **não muda** até pedido explícito.
- Sobre `paper` (fundo claro futuro): traço `ink`; fan nas mesmas quatro cores.

---

## Hierarquia em peças gráficas

1. Fundo `ink`.
2. Texto principal em `paper`; ênfase / segunda linha em `magenta`.
3. `ochre` só em título secundário, pixels ou primeira anel do espectro.
4. `violet` e `indigo` em geometria (anéis, faixas), não em corpo de texto longo.

Motivos permitidos (esparsos): faixas horizontais no topo (`magenta` / `paper` / `violet`→`indigo`); quadrados de 4–6 px (`magenta`, `ochre`, `violet`); semicírculos concêntricos na base (`ochre` → `magenta` → `violet` → `indigo`). Sem chrome, glassmorphism, néon ou gradiente excepto esses anéis.

Tipografia de marca: sans geométrica pesada, caixa alta no slogan. Não misturar serif.

---

## Fora de âmbito até pedido explícito

Não aplicar esta paleta a:

- `Prism/Assets.xcassets/AppIcon.appiconset/`
- `Prism/Assets.xcassets/AccentColor.colorset/` (hoje ~`#6E58FC`)
- `Prism/Design/PrismGlyph.swift` e ícone template da barra de menus
- `Prism/Design/QTDesign.swift` e chrome de UI
- `docs/readme/*` (ícone de vidro + SVGs em papel quente `#F6F3EC` / tinta `#1C1B19`)

Esses ficheiros são a identidade **em produção**. Esta paleta é o padrão **para trabalho novo** de logo e identidade, quando for pedido.

---

## Identidade actual (legado, em produção)

- Ícone: prisma de vidro 3D + espectro óptico de sete cores em fundo off-white.
- README / SVGs: papel quente, tinta quente, acento azul `#3B6FD4`.
- AccentColor do app: violeta-azul ~`#6E58FC`.

Não misturar as duas paletas na mesma peça. Peça nova → só tokens desta página. Peça já publicada → não retocar.
