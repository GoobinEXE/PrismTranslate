# Guia de Release — Prism

Passo a passo para gerar, assinar, notarizar e publicar uma versão do Prism fora da Mac App Store (distribuição direta via Developer ID + GitHub Releases).

> **Atalho:** o script [`scripts/release.sh`](scripts/release.sh) automatiza tudo (archive → export → notarização → staple → DMG). Este documento explica cada etapa manualmente e serve de referência quando algo der errado.

---

## 1. Requisitos

- **Apple Developer Program** ativo (US$ 99/ano) — necessário para Developer ID e notarização.
- **Certificado "Developer ID Application"** instalado no Keychain da máquina de build.
  - Crie em [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates) ou pelo Xcode (Settings → Accounts → Manage Certificates → “+” → Developer ID Application).
  - Verifique com:

    ```bash
    security find-identity -v -p codesigning | grep "Developer ID Application"
    ```

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

## 3. Notarização

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

## 4. Criar o DMG (apenas `hdiutil`, sem ferramentas de terceiros)

```bash
VERSION=1.0.0
STAGING=build/dmg-staging
rm -rf "$STAGING" && mkdir -p "$STAGING"

# Copia o app já notarizado/stapled e cria o atalho para /Applications
cp -R build/export/Prism.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Gera o DMG comprimido (UDZO), somente leitura
hdiutil create \
  -volname "Prism $VERSION" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "build/Prism-$VERSION.dmg"
```

Assine o DMG também (recomendado) e valide:

```bash
codesign --sign "Developer ID Application" --timestamp "build/Prism-$VERSION.dmg"
spctl --assess --type open --context context:primary-signature -v "build/Prism-$VERSION.dmg"
```

> Opcional: também é possível notarizar e staplear o próprio DMG (`notarytool submit` + `stapler staple` no `.dmg`). Como o `.app` dentro dele já está stapled, isso é redundante mas melhora a experiência de primeira abertura sem internet.

---

## 5. Primeira execução — instruções para o usuário final (Gatekeeper)

Inclua isto na página de release / README:

1. Abra o DMG e arraste **Prism** para a pasta **Aplicativos**.
2. Abra o app. Como foi notarizado pela Apple, o macOS mostra apenas um aviso informando que foi baixado da internet — clique em **Abrir**.
   - Se o macOS bloquear (“não pode ser aberto”): vá em **Ajustes do Sistema → Privacidade e Segurança**, role até o final e clique em **Abrir Mesmo Assim**.
3. O app pedirá as permissões necessárias (o onboarding guia o processo):
   - **Acessibilidade** — Ajustes do Sistema → Privacidade e Segurança → **Acessibilidade** → habilite **Prism**. Necessária para ler e substituir o texto do campo focado.
   - **Monitoramento de Entrada** — Ajustes do Sistema → Privacidade e Segurança → **Monitoramento de Entrada** → habilite **Prism**. Necessária para os atalhos globais (⌃⌥T / ⌃⌥⏎).
4. Após conceder as permissões, pode ser preciso **encerrar e reabrir o app** para que passem a valer.
5. O ícone de prisma aparece na barra de menus — pronto para usar.

> Se o usuário atualizar o app substituindo o binário, o macOS pode exigir reconceder as permissões (desmarcar e marcar de novo nas listas acima).

---

## 6. Publicar no GitHub Releases

1. Atualize o [`CHANGELOG.md`](CHANGELOG.md): mova as mudanças de “Unreleased” para a versão com a data do release.
2. Confirme que `MARKETING_VERSION` no Xcode bate com a versão do changelog.
3. Crie a tag e o release:

   ```bash
   git tag -a v1.0.0 -m "Prism 1.0.0"
   git push origin v1.0.0

   gh release create v1.0.0 \
     build/Prism-1.0.0.dmg \
     --title "Prism 1.0.0" \
     --notes-file <(sed -n '/## \[1.0.0\]/,/^## /p' CHANGELOG.md | sed '$d')
   ```

   (Ou crie o release pela interface web e anexe o DMG manualmente.)

4. Publique um checksum junto às notas, para o usuário verificar o download:

   ```bash
   shasum -a 256 build/Prism-1.0.0.dmg
   ```

---

## 7. Checklist rápido de release

- [ ] Versão bumpada (`MARKETING_VERSION`) e `CHANGELOG.md` atualizado
- [ ] `security find-identity` mostra o certificado Developer ID Application
- [ ] Archive + export OK (`codesign --verify` sem erros)
- [ ] `notarytool submit --wait` → **Accepted**
- [ ] `stapler validate` OK
- [ ] DMG criado, assinado e testado em uma máquina/conta limpa
- [ ] Tag + GitHub Release com DMG e checksum publicados
