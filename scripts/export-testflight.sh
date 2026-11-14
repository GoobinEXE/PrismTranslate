#!/usr/bin/env bash
#
# export-testflight.sh — Archive + export Mac App Store .pkg para Transporter / TestFlight.
#
# Usa PrismAppStore.entitlements (sandbox ON). Community / Developer ID continuam
# com Prism.entitlements (sandbox OFF).
#
# USO:
#   ./scripts/export-testflight.sh
#
# SAÍDA:
#   build/testflight/Prism.pkg  (ou Prism*.pkg — caminho impresso no final)
#
# Pré-requisitos:
#   - Apple Distribution no Keychain
#   - App no App Store Connect com bundle dev.prism.tradutor
#   - Xcode logado na conta do team UXJP4APP32
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/Prism.xcodeproj"
SCHEME="Prism"
APP_NAME="Prism"
BUNDLE_ID="dev.prism.tradutor"
TEAM_ID="${TEAM_ID:-UXJP4APP32}"
BUILD_DIR="$REPO_ROOT/build/testflight"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="$REPO_ROOT/packaging/ExportOptions-AppStore.plist"
APPSTORE_ENTS="$REPO_ROOT/Prism/PrismAppStore.entitlements"

XCODEBUILD="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}/usr/bin/xcodebuild"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; RESET=""
fi

info()  { echo "${GREEN}==>${RESET} $*"; }
warn()  { echo "${YELLOW}aviso:${RESET} $*"; }
die()   { echo "${RED}erro:${RESET} $*" >&2; exit 1; }

[[ -x "$XCODEBUILD" ]] || die "xcodebuild não encontrado em $XCODEBUILD"
[[ -d "$PROJECT" ]] || die "Projeto não encontrado: $PROJECT"
[[ -f "$EXPORT_PLIST" ]] || die "ExportOptions ausente: $EXPORT_PLIST"
[[ -f "$APPSTORE_ENTS" ]] || die "Entitlements App Store ausentes: $APPSTORE_ENTS"

DIST_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Distribution/ { print $2; exit }')"
[[ -n "$DIST_IDENTITY" ]] \
  || die "Nenhum 'Apple Distribution' no Keychain. Crie em Xcode → Settings → Accounts → Manage Certificates."

info "Apple Distribution: $DIST_IDENTITY"
info "Team: $TEAM_ID | Bundle: $BUNDLE_ID"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

info "1/3 Archive (Release + sandbox App Store)…"
"$XCODEBUILD" archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_ENTITLEMENTS=Prism/PrismAppStore.entitlements \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  | tee "$BUILD_DIR/archive.log" | tail -20

[[ -d "$ARCHIVE_PATH" ]] || die "Archive falhou. Log: $BUILD_DIR/archive.log"

APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
[[ -d "$APP_IN_ARCHIVE" ]] || die "App ausente no archive: $APP_IN_ARCHIVE"

info "Verificando sandbox no archive…"
ENTS_DUMP="$(codesign -d --entitlements :- "$APP_IN_ARCHIVE" 2>/dev/null || true)"
echo "$ENTS_DUMP" | rg -q "com.apple.security.app-sandbox" \
  || die "Entitlements sem app-sandbox no binário arquivado."
if echo "$ENTS_DUMP" | rg -q "<key>com.apple.security.app-sandbox</key>[[:space:]]*<false/>"; then
  die "Sandbox ainda está false no archive — recusou envio App Store."
fi
info "Sandbox OK no archive."

info "2/3 Export App Store Connect (.pkg)…"
"$XCODEBUILD" -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  | tee "$BUILD_DIR/export.log" | tail -30

PKG_PATH="$(find "$EXPORT_DIR" -maxdepth 2 -name '*.pkg' -type f | head -1)"
[[ -n "$PKG_PATH" && -f "$PKG_PATH" ]] \
  || die "Export não gerou .pkg. Log: $BUILD_DIR/export.log
Conteúdo de $EXPORT_DIR:
$(ls -la "$EXPORT_DIR" 2>/dev/null || true)"

STABLE_PKG="$BUILD_DIR/$APP_NAME.pkg"
cp -f "$PKG_PATH" "$STABLE_PKG"

info "3/3 Pacote pronto para o Transporter:"
info "  $STABLE_PKG"
ls -lh "$STABLE_PKG"
echo
info "Próximo passo: abra o Transporter → Deliver → selecione esse .pkg"
warn "No TestFlight, conceda Acessibilidade (+ Monitoramento de Entrada) ao app instalado."
warn "Build sandboxed: atalhos CGEventTap podem falhar até o TCC estar concedido; Community zip permanece sem sandbox."
