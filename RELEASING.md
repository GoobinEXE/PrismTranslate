# Guia de Release — Prism

Passo a passo para gerar, assinar, notarizar e publicar uma versão do Prism fora da Mac App Store (distribuição direta via Developer ID + GitHub Releases).

O artefato público é um **`.dmg`**. Quem baixa **não precisa do Xcode**: o disco contém o instalador `.pkg` (recomendado) e o `.app` para arrastar para Aplicativos. Compilar a partir do código continua possível e é opcional — veja [`BUILDING.md`](BUILDING.md).

> **Atalho:** o script [`scripts/release.sh`](scripts/release.sh) automatiza tudo (archive → export → notarização → PKG → DMG). Este documento explica cada etapa manualmente e serve de referência quando algo der errado.

---

## 0. Tornar o repositório público (primeira vez)

Checklist **antes** do DMG / tag `v1.0.2`. Não rode isto no automático — é o passo seu, na hora de publicar.

- [ ] Confirme que não há secrets (`.env`, `Secrets.xcconfig`, chaves, `.p12`)
- [ ] `LICENSE` na raiz é a PolyForm Noncommercial 1.0.0; GitHub deve detectar a licença
- [ ] Remote: `GoobinEXE/PrismTranslate` (slug sem espaço; nome de exibição **Prism Translate**)
  - No GitHub: Settings → General → Repository name → `PrismTranslate` (hoje ainda é `QuickTranslate`)
  - Local: `git remote set-url origin https://github.com/GoobinEXE/PrismTranslate.git`
- [ ] Description do repo: app de menu bar para traduzir o campo focado; Topics: `macos`, `translation`, `menubar`
- [ ] Tornar o repositório **público**
- [ ] Tag anotada `v1.0.2` + GitHub Release com `Prism-1.0.2.dmg`

Versão do primeiro artefato público: **1.0.2**.

---

## 1. Requisitos

Estes requisitos são da **máquina que gera o DMG**, não do Mac de quem instala o app.

- **Apple Developer Program** ativo (US$ 99/ano) — necessário para Developer ID e notarização.
- **Certificado "Developer ID Application"** instalado no Keychain da máquina de build.
  - Crie em [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates) ou pelo Xcode (Settings → Accounts → Manage Certificates → “+” → Developer ID Application).
  - Verifique com:

    ```bash
    security find-identity -v -p codesigning | grep "Developer ID Application"
    ```

- **Certificado "Developer ID Installer"** (recomendado) — assina o `.pkg` que o usuário executa.
  - Crie o mesmo sítio, tipo **Developer ID Installer** (CSR no Keychain Access).
  - Verifique com: `security find-identity -v | grep "Developer ID Installer"`
  - Sem este certificado o script ainda gera o `.pkg`, mas o instalador pode ser recusado pelo Gatekeeper até você criar o cert.
- **Xcode 16+** com Command Line Tools funcionando (`xcodebuild -version`).
- **Credencial para notarização** (uma das duas):
  - **Perfil no Keychain** (recomendado — evita senha em variável de ambiente):

    ```bash
    xcrun notarytool store-credentials "prism-notary" \
      --apple-id "seu@apple-id.com" \
      --team-id "SEU_TEAM_ID" \
      --password "senha-de-app"
    ```

  - **App-Specific Password** gerado em [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords.

> **Nota sobre sandbox:** o app tem `com.apple.security.app-sandbox = false` no entitlements (necessário para Accessibility API e CGEvent tap). Isso é **perfeitamente aceitável para distribuição Developer ID**, mas **impede a publicação na Mac App Store**, que exige sandbox. A distribuição planejada é fora da loja mesmo.

---

## 2. Archive e export com assinatura Developer ID

O projeto já está configurado com **Hardened Runtime habilitado** (`ENABLE_HARDENED_RUNTIME = YES`), que é obrigatório para notarização.

### 2.1 Archive

```bash
xcodebuild archive \
  -project Prism.xcodeproj \
  -scheme Prism \
  -configuration Release \
  -archivePath build/Prism.xcarchive \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="SEU_TEAM_ID"
```

### 2.2 Export

Crie um `ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>SEU_TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
```

E exporte:

```bash
xcodebuild -exportArchive \
  -archivePath build/Prism.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export
```

O `.app` assinado fica em `build/export/Prism.app`. Confira a assinatura:

```bash
codesign --verify --deep --strict --verbose=2 build/export/Prism.app
codesign -dv --entitlements - build/export/Prism.app
```

---

## 3. Notarização do .app

A Apple exige notarização para apps distribuídos fora da loja (senão o Gatekeeper bloqueia).

### 3.1 Compactar e enviar

```bash
ditto -c -k --keepParent build/export/Prism.app build/Prism.zip
```

Com perfil do Keychain:

```bash
xcrun notarytool submit build/Prism.zip \
  --keychain-profile "prism-notary" \
  --wait
```

Ou com credenciais explícitas:

```bash
xcrun notarytool submit build/Prism.zip \
  --apple-id "seu@apple-id.com" \
  --team-id "SEU_TEAM_ID" \
  --password "senha-de-app" \
  --wait
```

Aguarde o status `Accepted`. Se for `Invalid`, veja o log:

```bash
xcrun notarytool log <submission-id> --keychain-profile "prism-notary"
```

### 3.2 Staple

Anexa o ticket de notarização ao app (permite validação offline pelo Gatekeeper):

```bash
xcrun stapler staple build/export/Prism.app
xcrun stapler validate build/export/Prism.app
```

---

## 4. Instalador `.pkg` (sem Xcode no Mac de destino)

O Prism é um `.app` autocontido: não há Homebrew, Python, CLT nem runtime extra para o usuário instalar. O `.pkg` ainda assim faz três coisas úteis:

1. **Recusa macOS anterior ao 15** (`preinstall` + `allowed-os-versions` no `packaging/distribution.xml`)
2. **Copia** `Prism.app` para `/Applications`
3. **Abre o app** na conta do usuário logado (`postinstall`), para o onboarding pedir permissões e o Prism baixar pacotes de idioma da Apple se faltarem

Scripts e textos do instalador estão em [`packaging/`](packaging/). O `scripts/release.sh` corre `pkgbuild` + `productbuild`, assina com **Developer ID Installer** (se existir), notariza e stapleia o `.pkg`.

Resumo manual:

```bash
VERSION=1.0.2
pkgbuild \
  --root build/pkg-root \
  --identifier com.marcelopessoa.prism \
  --version "$VERSION" \
  --install-location /Applications \
  --scripts packaging/scripts \
  --min-os-version 15.0 \
  build/Prism-component.pkg

productbuild \
  --distribution packaging/distribution.xml \
  --package-path build \
  --resources packaging/resources \
  build/Prism-$VERSION-unsigned.pkg

productsign --sign "Developer ID Installer" --timestamp \
  build/Prism-$VERSION-unsigned.pkg build/Prism-$VERSION.pkg

xcrun notarytool submit build/Prism-$VERSION.pkg --keychain-profile "prism-notary" --wait
xcrun stapler staple build/Prism-$VERSION.pkg
```

(Substitua a versão em `packaging/distribution.xml` — o `__VERSION__` — se estiver a gerar o XML à mão. O script de release faz esse `sed`.)

---

## 5. Criar o DMG (apenas `hdiutil`, sem ferramentas de terceiros)

O disco contém o instalador **e** o arrastar-para-Aplicativos:

```bash
VERSION=1.0.2
STAGING=build/dmg-staging
rm -rf "$STAGING" && mkdir -p "$STAGING"

cp -R build/export/Prism.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "build/Prism-$VERSION.pkg" "$STAGING/Instalar Prism.pkg"
cp packaging/resources/Como\ instalar.txt "$STAGING/Como instalar.txt"

hdiutil create \
  -volname "Prism $VERSION" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "build/Prism-$VERSION.dmg"
```

Assine o DMG, notarize e staple (o script faz os três):

```bash
codesign --sign "Developer ID Application" --timestamp "build/Prism-$VERSION.dmg"
xcrun notarytool submit "build/Prism-$VERSION.dmg" --keychain-profile "prism-notary" --wait
xcrun stapler staple "build/Prism-$VERSION.dmg"
spctl --assess --type open --context context:primary-signature -v "build/Prism-$VERSION.dmg"
```

Anexe **só o DMG** no GitHub Release. O `.pkg` já vai dentro. Quem clona o repo para abrir no Xcode usa o zip de código-fonte que o GitHub gera automaticamente na tag — é o caminho opcional.

---

## 6. Primeira execução — instruções para o usuário final (Gatekeeper)

Inclua isto na página de release / README:

1. Abra o DMG e dê dois cliques em **Instalar Prism** (ou arraste **Prism** para **Aplicativos**).
2. Abra o app se o instalador não o tiver aberto. Como foi notarizado pela Apple, o macOS mostra apenas um aviso informando que foi baixado da internet — clique em **Abrir**.
   - Se o macOS bloquear (“não pode ser aberto”): vá em **Ajustes do Sistema → Privacidade e Segurança**, role até o final e clique em **Abrir Mesmo Assim**.
3. O app pedirá as permissões necessárias (o onboarding guia o processo):
   - **Acessibilidade** — Ajustes do Sistema → Privacidade e Segurança → **Acessibilidade** → habilite **Prism**. Necessária para ler e substituir o texto do campo focado.
   - **Monitoramento de Entrada** — Ajustes do Sistema → Privacidade e Segurança → **Monitoramento de Entrada** → habilite **Prism**. Necessária para os atalhos globais (⌃⌥T / ⌃⌥⏎).
4. Após conceder as permissões, pode ser preciso **encerrar e reabrir o app** para que passem a valer.
5. O ícone de prisma aparece na barra de menus — pronto para usar.

> Se o usuário atualizar o app substituindo o binário, o macOS pode exigir reconceder as permissões (desmarcar e marcar de novo nas listas acima).

---

## 7. Publicar no GitHub Releases

1. Atualize o [`CHANGELOG.md`](CHANGELOG.md): mova as mudanças de “Unreleased” para a versão com a data do release.
2. Confirme que `MARKETING_VERSION` no Xcode bate com a versão do changelog.
3. Crie a tag e o release:

   ```bash
   git tag -a v1.0.2 -m "Prism 1.0.2"
   git push origin v1.0.2

   gh release create v1.0.2 \
     build/Prism-1.0.2.dmg \
     --title "Prism 1.0.2" \
     --notes-file <(sed -n '/## \[1.0.2\]/,/^## /p' CHANGELOG.md | sed '$d')
   ```

   (Ou crie o release pela interface web e anexe o DMG manualmente.)

4. Publique um checksum junto às notas, para o usuário verificar o download:

   ```bash
   shasum -a 256 build/Prism-1.0.2.dmg
   ```

Não anexe o projeto Xcode nem peça Xcode nas notas do release. O zip de código-fonte da tag já cobre quem quer compilar.

---

## 8. Checklist rápido de release

- [ ] Versão bumpada (`MARKETING_VERSION`) e `CHANGELOG.md` atualizado
- [ ] `security find-identity` mostra Developer ID Application (e, de preferência, Developer ID Installer)
- [ ] Archive + export OK (`codesign --verify` sem erros)
- [ ] `notarytool submit --wait` → **Accepted** no `.app`, no `.pkg` e no `.dmg`
- [ ] `stapler validate` OK nos três
- [ ] DMG testado numa máquina/conta **sem Xcode**
- [ ] Tag + GitHub Release com o DMG e o checksum publicados
