#!/usr/bin/env bash
#
# release.sh — Automatiza o release do Prism:
#   archive → export (Developer ID) → notarização → staple → PKG → DMG
#
# O DMG é o artefato para o usuário final: não precisa de Xcode.
# Contém o instalador .pkg (caminho recomendado) e o .app para arrastar
# para Aplicativos. Compilar a partir do código (BUILDING.md) continua opcional.
#
# USO:
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=prism-notary ./scripts/release.sh
#   # ou, sem perfil no Keychain:
#   TEAM_ID=ABCDE12345 APPLE_ID=voce@exemplo.com APP_PASSWORD=xxxx-xxxx-xxxx-xxxx ./scripts/release.sh
#
# VARIÁVEIS DE AMBIENTE:
#   TEAM_ID         (obrigatória)  Team ID da conta Apple Developer (ex.: ABCDE12345)
#   NOTARY_PROFILE  (opção A)      Nome do perfil salvo via `xcrun notarytool store-credentials`
#   APPLE_ID        (opção B)      Apple ID usado na notarização
#   APP_PASSWORD    (opção B)      App-Specific Password (account.apple.com)
#   VERSION         (opcional)     Versão do release; padrão: MARKETING_VERSION do projeto
#   SKIP_NOTARIZE   (opcional)     Se "1", pula notarização/staple (apenas para testes locais!)
#
# Pré-requisitos (máquina de *build*, não do usuário final):
#   Xcode + CLT, certificado "Developer ID Application", credenciais de notarização.
#   "Developer ID Installer" é recomendado para assinar o .pkg; se faltar, o script
#   avisa e segue (o .app e o .dmg ainda são assinados).
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/Prism.xcodeproj"
SCHEME="Prism"
APP_NAME="Prism"
BUNDLE_ID="com.marcelopessoa.prism"
PACKAGING_DIR="$REPO_ROOT/packaging"

BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
STAGING_DIR="$BUILD_DIR/dmg-staging"
PKG_ROOT="$BUILD_DIR/pkg-root"
PKG_SCRIPTS="$BUILD_DIR/pkg-scripts"
PKG_RESOURCES="$BUILD_DIR/pkg-resources"
COMPONENT_PKG="$BUILD_DIR/Prism-component.pkg"
DIST_XML="$BUILD_DIR/distribution.xml"

# Cores só quando o stdout é um terminal
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

info()  { echo "${GREEN}==>${RESET} $*"; }
warn()  { echo "${YELLOW}aviso:${RESET} $*"; }
die()   { echo "${RED}erro:${RESET} $*" >&2; exit 1; }

find_identity() {
  local needle="$1"
  security find-identity -v 2>/dev/null | awk -F'"' -v n="$needle" '$0 ~ n { print $2; exit }'
}

notarize_submit() {
  local artifact="$1"
  xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait \
    || die "Notarização recusada ($artifact). Veja o log com: xcrun notarytool log <submission-id> ${NOTARY_ARGS[*]}"
}

# ---------------------------------------------------------------------------
# Verificações de pré-requisitos (fail fast) — só na máquina que *gera* o DMG
# ---------------------------------------------------------------------------
info "Verificando pré-requisitos de build…"

command -v xcodebuild >/dev/null 2>&1 \
  || die "xcodebuild não encontrado. Instale o Xcode e rode: xcode-select --switch /Applications/Xcode.app"

xcodebuild -version >/dev/null 2>&1 \
  || die "xcodebuild não está funcional nesta máquina. Verifique a instalação do Xcode/CLT."

[[ -d "$PROJECT" ]] \
  || die "Projeto não encontrado em: $PROJECT (rode o script a partir do repositório)."

[[ -d "$PACKAGING_DIR/scripts" ]] \
  || die "Pasta de empacotamento ausente: $PACKAGING_DIR"

[[ -n "${TEAM_ID:-}" ]] \
  || die "Defina TEAM_ID (Team ID da conta Apple Developer, ex.: TEAM_ID=ABCDE12345)."

APP_IDENTITY="$(find_identity "Developer ID Application")"
[[ -n "$APP_IDENTITY" ]] \
  || die "Nenhum certificado 'Developer ID Application' no Keychain.
Crie em developer.apple.com (Certificates) ou pelo Xcode → Settings → Accounts → Manage Certificates."

INSTALLER_IDENTITY="$(find_identity "Developer ID Installer")"
if [[ -z "$INSTALLER_IDENTITY" ]]; then
  warn "Nenhum certificado 'Developer ID Installer'. O .pkg sai sem assinatura de instalador.
Crie um em developer.apple.com → Certificates → Developer ID Installer. O .app e o .dmg continuam assinados."
fi

# Credenciais de notarização: perfil do Keychain OU Apple ID + senha de app
NOTARY_ARGS=()
if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  warn "SKIP_NOTARIZE=1 — a notarização será PULADA. Não distribua este build!"
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APP_PASSWORD:-}" ]]; then
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD")
else
  die "Credenciais de notarização ausentes. Defina NOTARY_PROFILE
(criado com: xcrun notarytool store-credentials) OU o par APPLE_ID + APP_PASSWORD."
fi

# Versão: usa VERSION do ambiente ou lê MARKETING_VERSION do projeto
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/MARKETING_VERSION/ {print $2; exit}')"
  [[ -n "$VERSION" ]] || die "Não foi possível ler MARKETING_VERSION. Defina VERSION=x.y.z manualmente."
fi

DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
PKG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.pkg"
info "Release do $APP_NAME versão $VERSION (Team: $TEAM_ID)"

mkdir -p "$BUILD_DIR"

# ---------------------------------------------------------------------------
# 1. Archive (Release, assinatura Developer ID)
# ---------------------------------------------------------------------------
info "1/8 Gerando archive…"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  | tail -5

[[ -d "$ARCHIVE_PATH" ]] || die "Archive falhou: $ARCHIVE_PATH não foi criado."

# ---------------------------------------------------------------------------
# 2. Export do .app assinado
# ---------------------------------------------------------------------------
info "2/8 Exportando .app com Developer ID…"

cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
PLIST

rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_DIR" \
  | tail -5

[[ -d "$APP_PATH" ]] || die "Export falhou: $APP_PATH não foi criado."

info "Verificando assinatura…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" \
  || die "Assinatura inválida no .app exportado."

# ---------------------------------------------------------------------------
# 3. Notarização do .app
# ---------------------------------------------------------------------------
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  info "3/8 Enviando o .app para notarização (pode levar alguns minutos)…"
  ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  notarize_submit "$ZIP_PATH"

  info "Aplicando staple no .app…"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH" || die "Staple inválido no .app."
else
  warn "3/8 pulado (SKIP_NOTARIZE=1)."
fi

# ---------------------------------------------------------------------------
# 4. PKG — instalador que não exige Xcode no Mac de destino
# ---------------------------------------------------------------------------
info "4/8 Montando o instalador .pkg…"
rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "$PKG_RESOURCES" "$COMPONENT_PKG" "$PKG_PATH"
mkdir -p "$PKG_ROOT" "$PKG_SCRIPTS" "$PKG_RESOURCES"

ditto "$APP_PATH" "$PKG_ROOT/$APP_NAME.app"

cp "$PACKAGING_DIR/scripts/preinstall" "$PKG_SCRIPTS/preinstall"
cp "$PACKAGING_DIR/scripts/postinstall" "$PKG_SCRIPTS/postinstall"
chmod 755 "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS/postinstall"

# Recurso da licença: o Installer.app mostra o texto PolyForm na etapa legal.
cp "$REPO_ROOT/LICENSE" "$PKG_RESOURCES/LICENSE"
cp "$PACKAGING_DIR/resources/welcome.html" "$PKG_RESOURCES/welcome.html"
cp "$PACKAGING_DIR/resources/conclusion.html" "$PKG_RESOURCES/conclusion.html"

pkgbuild \
  --root "$PKG_ROOT" \
  --identifier "$BUNDLE_ID" \
  --version "$VERSION" \
  --install-location /Applications \
  --scripts "$PKG_SCRIPTS" \
  --min-os-version 15.0 \
  "$COMPONENT_PKG"

sed "s/__VERSION__/${VERSION}/g" "$PACKAGING_DIR/distribution.xml" > "$DIST_XML"

UNSIGNED_PKG="$BUILD_DIR/$APP_NAME-$VERSION-unsigned.pkg"
productbuild \
  --distribution "$DIST_XML" \
  --package-path "$BUILD_DIR" \
  --resources "$PKG_RESOURCES" \
  "$UNSIGNED_PKG"

if [[ -n "$INSTALLER_IDENTITY" ]]; then
  info "Assinando o .pkg com Developer ID Installer…"
  productsign --sign "$INSTALLER_IDENTITY" --timestamp "$UNSIGNED_PKG" "$PKG_PATH"
  rm -f "$UNSIGNED_PKG"
else
  mv "$UNSIGNED_PKG" "$PKG_PATH"
fi

[[ -f "$PKG_PATH" ]] || die "Falha ao criar o instalador: $PKG_PATH"

# ---------------------------------------------------------------------------
# 5. Notarização do .pkg
# ---------------------------------------------------------------------------
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  info "5/8 Enviando o .pkg para notarização…"
  notarize_submit "$PKG_PATH"
  xcrun stapler staple "$PKG_PATH"
  xcrun stapler validate "$PKG_PATH" || die "Staple inválido no .pkg."
else
  warn "5/8 pulado (SKIP_NOTARIZE=1)."
fi

# ---------------------------------------------------------------------------
# 6. DMG — artefato único do GitHub Release
# ---------------------------------------------------------------------------
info "6/8 Criando DMG…"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$PKG_PATH" "$STAGING_DIR/Instalar $APP_NAME.pkg"
cp "$PACKAGING_DIR/resources/Como instalar.txt" "$STAGING_DIR/Como instalar.txt"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

info "Assinando o DMG…"
codesign --sign "$APP_IDENTITY" --timestamp "$DMG_PATH"

# ---------------------------------------------------------------------------
# 7. Notarização do DMG (abertura sem internet na primeira vez)
# ---------------------------------------------------------------------------
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  info "7/8 Enviando o DMG para notarização…"
  notarize_submit "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH" || die "Staple inválido no DMG."
else
  warn "7/8 pulado (SKIP_NOTARIZE=1)."
fi

# ---------------------------------------------------------------------------
# 8. Resumo final
# ---------------------------------------------------------------------------
info "8/8 Concluído!"
echo ""
echo "  App:      $APP_PATH"
echo "  PKG:      $PKG_PATH"
echo "  DMG:      $DMG_PATH"
echo "  SHA-256:  $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "O DMG é o ficheiro a anexar no GitHub Release. Quem baixa não precisa de Xcode:"
echo "  • recomendado: dois cliques em «Instalar Prism.pkg»"
echo "  • alternativa: arrastar Prism para Aplicativos"
echo ""
echo "Próximos passos:"
echo "  1. Teste o DMG numa máquina/conta sem Xcode"
echo "  2. Confirme o CHANGELOG.md e a tag v$VERSION"
echo "  3. Publique no GitHub Releases (veja RELEASING.md, seção 6)"
