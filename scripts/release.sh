#!/usr/bin/env bash
#
# release.sh — Automatiza o release do QuickTranslate:
#   archive → export (Developer ID) → notarização → staple → DMG
#
# USO:
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=quicktranslate-notary ./scripts/release.sh
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
# Pré-requisitos: Xcode + CLT funcionando, certificado "Developer ID Application"
# no Keychain, e credenciais de notarização (perfil OU Apple ID + senha de app).
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/QuickTranslate.xcodeproj"
SCHEME="QuickTranslate"
APP_NAME="QuickTranslate"

BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
STAGING_DIR="$BUILD_DIR/dmg-staging"

# Cores só quando o stdout é um terminal
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

info()  { echo "${GREEN}==>${RESET} $*"; }
warn()  { echo "${YELLOW}aviso:${RESET} $*"; }
die()   { echo "${RED}erro:${RESET} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Verificações de pré-requisitos (fail fast)
# ---------------------------------------------------------------------------
info "Verificando pré-requisitos…"

command -v xcodebuild >/dev/null 2>&1 \
  || die "xcodebuild não encontrado. Instale o Xcode e rode: xcode-select --switch /Applications/Xcode.app"

xcodebuild -version >/dev/null 2>&1 \
  || die "xcodebuild não está funcional nesta máquina. Verifique a instalação do Xcode/CLT."

[[ -d "$PROJECT" ]] \
  || die "Projeto não encontrado em: $PROJECT (rode o script a partir do repositório)."

[[ -n "${TEAM_ID:-}" ]] \
  || die "Defina TEAM_ID (Team ID da conta Apple Developer, ex.: TEAM_ID=ABCDE12345)."

# Certificado Developer ID Application no Keychain
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  die "Nenhum certificado 'Developer ID Application' no Keychain.
Crie em developer.apple.com (Certificates) ou pelo Xcode → Settings → Accounts → Manage Certificates."
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
info "Release do $APP_NAME versão $VERSION (Team: $TEAM_ID)"

# ---------------------------------------------------------------------------
# 1. Archive (Release, assinatura Developer ID)
# ---------------------------------------------------------------------------
info "1/6 Gerando archive…"
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
info "2/6 Exportando .app com Developer ID…"

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
# 3. Notarização
# ---------------------------------------------------------------------------
if [[ "${SKIP_NOTARIZE:-0}" != "1" ]]; then
  info "3/6 Enviando para notarização (pode levar alguns minutos)…"
  ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  # --wait bloqueia até a Apple concluir; falha se o status não for Accepted
  xcrun notarytool submit "$ZIP_PATH" "${NOTARY_ARGS[@]}" --wait \
    || die "Notarização recusada. Veja o log com: xcrun notarytool log <submission-id> ${NOTARY_ARGS[*]}"

  # -------------------------------------------------------------------------
  # 4. Staple (anexa o ticket ao app para validação offline)
  # -------------------------------------------------------------------------
  info "4/6 Aplicando staple…"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH" || die "Staple inválido."
else
  warn "3/6 e 4/6 pulados (SKIP_NOTARIZE=1)."
fi

# ---------------------------------------------------------------------------
# 5. Criação do DMG (hdiutil, sem ferramentas de terceiros)
# ---------------------------------------------------------------------------
info "5/6 Criando DMG…"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

info "Assinando o DMG…"
codesign --sign "Developer ID Application" --timestamp "$DMG_PATH"

# ---------------------------------------------------------------------------
# 6. Resumo final
# ---------------------------------------------------------------------------
info "6/6 Concluído!"
echo ""
echo "  App:      $APP_PATH"
echo "  DMG:      $DMG_PATH"
echo "  SHA-256:  $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo ""
echo "Próximos passos:"
echo "  1. Teste o DMG em uma máquina/conta limpa"
echo "  2. Atualize o CHANGELOG.md e crie a tag v$VERSION"
echo "  3. Publique no GitHub Releases (veja RELEASING.md, seção 6)"
