#!/usr/bin/env bash
#
# package-community.sh — Build Release sem Developer ID e gera zip para Homebrew / GitHub Releases.
#
# Não exige Apple Developer Program nem notarização. O usuário final instala via Homebrew
# (veja INSTALL.md) ou baixa o zip manualmente.
#
# USO:
#   ./scripts/package-community.sh
#   VERSION=1.0.2 ./scripts/package-community.sh
#
# SAÍDA:
#   build/Prism-<versão>.zip
#   SHA-256 impresso no final (atualize o cask em packaging/homebrew/Casks/prism-translate.rb)
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/Prism.xcodeproj"
SCHEME="Prism"
APP_NAME="Prism"
BUILD_DIR="$REPO_ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Release"
APP_PATH="$PRODUCTS_DIR/$APP_NAME.app"
STAGING_DIR="$BUILD_DIR/zip-staging"

if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; RESET=""
fi

info()  { echo "${GREEN}==>${RESET} $*"; }
warn()  { echo "${YELLOW}aviso:${RESET} $*"; }
die()   { echo "${RED}erro:${RESET} $*" >&2; exit 1; }

XCODEBUILD="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}/usr/bin/xcodebuild"
[[ -x "$XCODEBUILD" ]] || die "xcodebuild não encontrado. Instale o Xcode.app."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

[[ -d "$PROJECT" ]] || die "Projeto não encontrado: $PROJECT"

if [[ -z "${VERSION:-}" ]]; then
  VERSION="$("$XCODEBUILD" -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/MARKETING_VERSION/ {print $2; exit}')"
  [[ -n "$VERSION" ]] || die "Não foi possível ler MARKETING_VERSION. Defina VERSION=x.y.z."
fi

ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"
CASK_PATH="$REPO_ROOT/packaging/homebrew/Casks/prism-translate.rb"

info "Empacotamento Community do $APP_NAME versão $VERSION (sem Developer ID)"

mkdir -p "$BUILD_DIR"
rm -rf "$DERIVED_DATA" "$STAGING_DIR"

info "1/3 Compilando Release (assinatura ad-hoc, sem Developer ID)…"
"$XCODEBUILD" build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  | tail -10

[[ -d "$APP_PATH" ]] || die "Build falhou: $APP_PATH não existe."

info "2/3 Assinando ad-hoc e verificando o bundle…"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --verbose=2 "$APP_PATH" || warn "Verificação ad-hoc falhou; o zip ainda será gerado."

BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [[ -n "$BUNDLE_VERSION" && "$BUNDLE_VERSION" != "$VERSION" ]]; then
  warn "CFBundleShortVersionString ($BUNDLE_VERSION) difere de MARKETING_VERSION ($VERSION)."
fi

info "3/3 Criando zip…"
rm -f "$ZIP_PATH"
mkdir -p "$STAGING_DIR"
ditto --norsrc --noextattr --noqtn "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
(
  cd "$STAGING_DIR"
  COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc --noextattr --noqtn \
    "$APP_NAME.app" "$ZIP_PATH"
)

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

if [[ -f "$CASK_PATH" ]]; then
  python3 - "$CASK_PATH" "$VERSION" "$SHA256" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
version, sha = sys.argv[2], sys.argv[3]
text = path.read_text()
text = re.sub(r'version\s+"[^"]+"', f'version "{version}"', text, count=1)
text = re.sub(r'sha256\s+"[^"]+"', f'sha256 "{sha}"', text, count=1)
path.write_text(text)
PY
  info "Cask atualizado: $CASK_PATH"
fi

info "Concluído!"
echo ""
echo "  Zip:      $ZIP_PATH"
echo "  SHA-256:  $SHA256"
echo ""
echo "Próximos passos:"
echo "  1. Anexe o zip num GitHub Release (tag v$VERSION)"
echo "  2. Publique o cask em GoobinEXE/homebrew-tap (veja packaging/homebrew/README.md)"
echo "  3. Teste: brew tap goobinexe/tap && brew trust --tap goobinexe/tap && brew install --cask prism-translate"
