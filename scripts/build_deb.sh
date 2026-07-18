#!/usr/bin/env bash
# Empacota o bundle Linux do Prosa (build/linux/x64/release/bundle) em um
# pacote .deb instalável via `sudo apt install ./prosa_<versão>_amd64.deb`.
#
# O bundle do `flutter build linux` já é autocontido em relação ao Flutter:
# o engine (libflutter_linux_gtk.so) e o código Dart compilado (libapp.so)
# vão dentro do pacote. As únicas dependências de runtime são bibliotecas
# de sistema padrão (GTK3, libsecret) — nada de `flutter`/Dart SDK é
# necessário na máquina de destino, só para compilar aqui.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUNDLE_DIR="build/linux/x64/release/bundle"
PKG_NAME="prosa"
VERSION="$(grep -m1 '^version:' pubspec.yaml | sed -E 's/version:\s*([0-9.]+).*/\1/')"
ARCH="amd64"
DIST_DIR="dist"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

if [ -z "$VERSION" ]; then
  echo "Não foi possível ler a versão em pubspec.yaml" >&2
  exit 1
fi

echo "=== Compilando bundle release ==="
flutter build linux --release

if [ ! -x "$BUNDLE_DIR/prosa" ]; then
  echo "Bundle não encontrado em $BUNDLE_DIR — build falhou?" >&2
  exit 1
fi

echo "=== Montando estrutura do pacote (versão $VERSION) ==="
INSTALL_DIR="$STAGE_DIR/opt/$PKG_NAME"
mkdir -p "$INSTALL_DIR" "$STAGE_DIR/usr/bin" \
  "$STAGE_DIR/usr/share/applications" \
  "$STAGE_DIR/usr/share/icons/hicolor/512x512/apps" \
  "$STAGE_DIR/DEBIAN"

cp -r "$BUNDLE_DIR"/. "$INSTALL_DIR/"

# Symlink em /usr/bin: o executável do Flutter resolve seu próprio caminho
# via /proc/self/exe, então funciona normalmente mesmo invocado via link.
ln -s "/opt/$PKG_NAME/prosa" "$STAGE_DIR/usr/bin/prosa"

# O .desktop já é gerado pelo `flutter build linux` com Exec=prosa e
# Icon=com.prosa.prosa — casa exatamente com o symlink e o ícone abaixo.
cp "$BUNDLE_DIR/share/applications/com.prosa.prosa.desktop" \
  "$STAGE_DIR/usr/share/applications/"

python3 - "$ROOT_DIR/assets/icon/icon.png" "$STAGE_DIR/usr/share/icons/hicolor/512x512/apps/com.prosa.prosa.png" <<'EOF'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
Image.open(src).resize((512, 512), Image.LANCZOS).save(dst)
EOF

cat > "$STAGE_DIR/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Section: editors
Priority: optional
Architecture: $ARCH
Depends: libgtk-3-0, libsecret-1-0
Maintainer: André Machado <andre.silva@smartgreen.net>
Description: Editor de texto para escritores
 Prosa é um editor de texto focado em escritores de livros, com
 integração Git via SSH e estrutura de projeto versionada.
EOF

cat > "$STAGE_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
exit 0
EOF

cat > "$STAGE_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -f /usr/share/icons/hicolor || true
exit 0
EOF

chmod 755 "$STAGE_DIR/DEBIAN/postinst" "$STAGE_DIR/DEBIAN/postrm"
find "$STAGE_DIR" -type d -exec chmod 755 {} \;
find "$STAGE_DIR" -type f -not -path "*/DEBIAN/*" -exec chmod 644 {} \;
chmod 755 "$INSTALL_DIR/prosa"

mkdir -p "$DIST_DIR"
OUT="$DIST_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$STAGE_DIR" "$OUT"

echo ""
echo "=== Pacote gerado: $OUT ==="
dpkg-deb --info "$OUT"
