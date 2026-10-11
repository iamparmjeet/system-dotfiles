#!/usr/bin/env bash
#
# setup-kde-omarchy-theming.sh
# ----------------------------------------------------------------------------
# Make KDE/Qt apps (Dolphin, Kate, Gwenview, ...) follow the active Omarchy
# theme uniformly: same colors as the system, same fonts as Nautilus, and
# visible toolbar icons. Re-themes automatically on every `omarchy theme set`.
#
# Safe to run multiple times. Run as your normal user (it will sudo only for
# the optional /etc/environment cleanup).
# ----------------------------------------------------------------------------
set -euo pipefail

CONF="$HOME/.config"
SCRIPTS="$CONF/omarchy/scripts"
HOOKS="$CONF/omarchy/hooks"
GEN="$SCRIPTS/gen-qt-theme.sh"
ENVCONF="$CONF/hypr/custom/env.conf"
QT6CT="$CONF/qt6ct/qt6ct.conf"

info() { printf '\033[1;32m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

# ----------------------------------------------------------------------------
# 1. Dependencies (best-effort; Fusion style itself is built into Qt)
# ----------------------------------------------------------------------------
PKGS=(qt6ct-kde breeze-icons yaru-icon-theme adwaita-fonts dolphin kate gwenview)
MISSING=()
for p in "${PKGS[@]}"; do
    pacman -Qq "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if ((${#MISSING[@]})); then
    info "Installing missing packages: ${MISSING[*]}"
    if command -v omarchy >/dev/null 2>&1; then
        omarchy pkg add "${MISSING[@]}" || warn "Some packages failed to install; continuing."
    else
        sudo pacman -S --needed --noconfirm "${MISSING[@]}" || warn "Some packages failed to install; continuing."
    fi
else
    info "All required packages already present."
fi

# ----------------------------------------------------------------------------
# 2. Qt environment: platform theme = qt6ct, widget style = Fusion
# ----------------------------------------------------------------------------
info "Configuring Qt environment ($ENVCONF)"
mkdir -p "$(dirname "$ENVCONF")"
touch "$ENVCONF"
# drop any prior Qt theme/style lines, then add ours
sed -i '/QT_QPA_PLATFORMTHEME/d; /QT_STYLE_OVERRIDE/d' "$ENVCONF"
{
    echo 'env = QT_QPA_PLATFORMTHEME,qt6ct'
    echo 'env = QT_STYLE_OVERRIDE,Fusion'
} >> "$ENVCONF"

# Remove conflicting kvantum override from /etc/environment (optional, sudo)
if grep -q '^QT_STYLE_OVERRIDE=kvantum' /etc/environment 2>/dev/null; then
    warn "/etc/environment forces QT_STYLE_OVERRIDE=kvantum — removing (needs sudo)."
    sudo sed -i '/^QT_STYLE_OVERRIDE=kvantum$/d' /etc/environment || \
        warn "Could not edit /etc/environment; your session env will still win after re-login."
fi

# ----------------------------------------------------------------------------
# 3. Base qt6ct.conf so the generator's in-place edits have keys to patch
# ----------------------------------------------------------------------------
mkdir -p "$(dirname "$QT6CT")"
if [[ ! -f "$QT6CT" ]]; then
    info "Creating base $QT6CT"
    cat > "$QT6CT" <<'EOF'
[Appearance]
color_scheme_path=
custom_palette=true
icon_theme=
standard_dialogs=default
style=Fusion

[Fonts]
fixed="Adwaita Mono,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
general="Adwaita Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"

[Interface]
activate_item_on_single_click=1
buttonbox_layout=0
cursor_flash_time=1000
dialog_buttons_have_icons=1
double_click_interval=400
gui_effects=@Invalid()
keyboard_scheme=2
menus_have_icons=true
show_shortcuts_in_context_menus=true
toolbutton_style=4
underline_shortcut=1
wheel_scroll_lines=3
EOF
fi

# ----------------------------------------------------------------------------
# 4. The generator: reads the active Omarchy theme -> KDE/Qt theming
# ----------------------------------------------------------------------------
info "Installing generator ($GEN)"
mkdir -p "$SCRIPTS"
cat > "$GEN" <<'GENEOF'
#!/usr/bin/env bash
# ~/.config/omarchy/scripts/gen-qt-theme.sh
#
# Generate KDE/Qt theming from the *active* Omarchy theme so KDE apps
# (Dolphin, Kate, Gwenview, ...) match the rest of the system uniformly.
set -euo pipefail

THEME_DIR="$HOME/.config/omarchy/current/theme"
COLORS_FILE="$THEME_DIR/colors.toml"
ICONS_FILE="$THEME_DIR/icons.theme"

SCHEME_FILE="$HOME/.local/share/color-schemes/OmarchyTheme.colors"
KDEGLOBALS="$HOME/.config/kdeglobals"
QT6CT="$HOME/.config/qt6ct/qt6ct.conf"

[[ -f "$COLORS_FILE" ]] || { echo "No colors.toml at $COLORS_FILE" >&2; exit 1; }

# --- parse colors.toml: key = "#rrggbb" ------------------------------------
get_hex() {
    sed -n "s/^$1[[:space:]]*=[[:space:]]*\"#\([0-9a-fA-F]\{6\}\).*/\1/p" "$COLORS_FILE" | head -n1
}
hex_to_rgb() {
    local h="$1"
    printf "%d,%d,%d" "$((16#${h:0:2}))" "$((16#${h:2:2}))" "$((16#${h:4:2}))"
}
rgb() {
    local h; h="$(get_hex "$1")"
    [[ -z "$h" ]] && h="$2"
    hex_to_rgb "$h"
}

# --- role mapping (semantic keys -> works for light & dark themes) ---------
BG=$(rgb background 282828)
SURFACE=$(rgb selection 504945)
ALT_SURFACE=$(rgb lighter_bg 3c3836)
FG=$(rgb foreground d4be98)
MUTED=$(rgb fg a89984)
ACCENT=$(rgb accent 7daea3)
SEL_BG=$(rgb selection_background d65d0e)
SEL_FG=$(rgb selection_foreground ebdbb2)
ERROR=$(rgb red ea6962)
SUCCESS=$(rgb green a9b665)
WARNING=$(rgb yellow d8a657)

MODE="$(sed -n 's/^mode[[:space:]]*=[[:space:]]*"\([a-z]*\)".*/\1/p' "$COLORS_FILE" | head -n1)"
MODE="${MODE:-dark}"

# Base icon theme = same as GTK/Nautilus (colorful folders/places/mimetypes).
ICON_BASE="$( [[ -f "$ICONS_FILE" ]] && tr -d '[:space:]' < "$ICONS_FILE" )"
ICON_BASE="${ICON_BASE:-Yaru}"

# Yaru only ships *symbolic* action icons with a hardcoded dark fill; GTK
# recolors them but Qt/Fusion does not, so toolbar icons render black.
# Build a hybrid theme: Breeze's recolorable action icons (KDE tints them to
# the scheme text color) + inherit the base theme for everything colorful.
ICON_THEME="OmarchyKde"
HYBRID="$HOME/.local/share/icons/$ICON_THEME"
[[ "$MODE" == "light" ]] && BREEZE="breeze" || BREEZE="breeze-dark"
BREEZE_ACTIONS="/usr/share/icons/$BREEZE/actions"
if [[ -d "$BREEZE_ACTIONS" ]]; then
    rm -rf "$HYBRID"
    mkdir -p "$HYBRID"
    ln -sfn "$BREEZE_ACTIONS" "$HYBRID/actions"
    dirlist=""; sections=""
    for d in "$BREEZE_ACTIONS"/*/; do
        sz="$(basename "$d")"
        [[ "$sz" =~ ^[0-9]+$ ]] || continue
        dirlist+="actions/$sz,"
        sections+="[actions/$sz]
Size=$sz
Context=Actions
Type=Threshold

"
    done
    cat > "$HYBRID/index.theme" <<EOF
[Icon Theme]
Name=$ICON_THEME
Comment=Yaru folders + Breeze actions for KDE apps (generated)
Inherits=$ICON_BASE,$BREEZE,hicolor
Directories=${dirlist%,}

$sections
EOF
else
    ICON_THEME="$ICON_BASE"
fi

# --- shared [Colors:*] block -----------------------------------------------
gen_colors() {
cat <<EOF
[ColorEffects:Disabled]
Color=$MUTED
ColorAmount=0.55
ColorEffect=3
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=$MUTED
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0

[Colors:Button]
BackgroundAlternate=$ALT_SURFACE
BackgroundNormal=$SURFACE
DecorationFocus=$ACCENT
DecorationHover=$ACCENT
ForegroundActive=$ACCENT
ForegroundInactive=$MUTED
ForegroundLink=$ACCENT
ForegroundNegative=$ERROR
ForegroundNeutral=$WARNING
ForegroundNormal=$FG
ForegroundPositive=$SUCCESS
ForegroundVisited=$MUTED

[Colors:Selection]
BackgroundAlternate=$ACCENT
BackgroundNormal=$SEL_BG
DecorationFocus=$ACCENT
DecorationHover=$ACCENT
ForegroundActive=$SEL_FG
ForegroundInactive=$MUTED
ForegroundLink=$SEL_FG
ForegroundNegative=$ERROR
ForegroundNeutral=$WARNING
ForegroundNormal=$SEL_FG
ForegroundPositive=$SUCCESS
ForegroundVisited=$MUTED

[Colors:Tooltip]
BackgroundAlternate=$ALT_SURFACE
BackgroundNormal=$SURFACE
DecorationFocus=$ACCENT
DecorationHover=$ACCENT
ForegroundActive=$ACCENT
ForegroundInactive=$MUTED
ForegroundLink=$ACCENT
ForegroundNegative=$ERROR
ForegroundNeutral=$WARNING
ForegroundNormal=$FG
ForegroundPositive=$SUCCESS
ForegroundVisited=$MUTED

[Colors:View]
BackgroundAlternate=$ALT_SURFACE
BackgroundNormal=$BG
DecorationFocus=$ACCENT
DecorationHover=$ACCENT
ForegroundActive=$ACCENT
ForegroundInactive=$MUTED
ForegroundLink=$ACCENT
ForegroundNegative=$ERROR
ForegroundNeutral=$WARNING
ForegroundNormal=$FG
ForegroundPositive=$SUCCESS
ForegroundVisited=$MUTED

[Colors:Window]
BackgroundAlternate=$ALT_SURFACE
BackgroundNormal=$BG
DecorationFocus=$ACCENT
DecorationHover=$ACCENT
ForegroundActive=$ACCENT
ForegroundInactive=$MUTED
ForegroundLink=$ACCENT
ForegroundNegative=$ERROR
ForegroundNeutral=$WARNING
ForegroundNormal=$FG
ForegroundPositive=$SUCCESS
ForegroundVisited=$MUTED

[Colors:Header]
BackgroundAlternate=$ALT_SURFACE
BackgroundNormal=$SURFACE
DecorationFocus=$ACCENT
DecorationHover=$ACCENT
ForegroundActive=$ACCENT
ForegroundInactive=$MUTED
ForegroundLink=$ACCENT
ForegroundNegative=$ERROR
ForegroundNeutral=$WARNING
ForegroundNormal=$FG
ForegroundPositive=$SUCCESS
ForegroundVisited=$MUTED
EOF
}

# --- 1. selectable KDE color scheme ----------------------------------------
mkdir -p "$(dirname "$SCHEME_FILE")"
{ gen_colors; cat <<EOF

[General]
ColorScheme=OmarchyTheme
Name=Omarchy Theme
shadeSortColumn=true

[KDE]
contrast=4
EOF
} > "$SCHEME_FILE"

# --- 2. kdeglobals (what KF apps actually read) ----------------------------
mkdir -p "$(dirname "$KDEGLOBALS")"
{ gen_colors; cat <<EOF

[General]
ColorScheme=OmarchyTheme
Name=Omarchy Theme
shadeSortColumn=true

[KDE]
contrast=4
widgetStyle=Fusion

[Icons]
Theme=$ICON_THEME
EOF
} > "$KDEGLOBALS"

# --- 3. fonts: match the GTK/system font (what Nautilus uses) --------------
gfont="$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")"
gmono="$(gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null | tr -d "'")"
gfont="${gfont:-Adwaita Sans 11}"; gmono="${gmono:-Adwaita Mono 11}"
gfam="${gfont% *}"; gsize="${gfont##* }"; mfam="${gmono% *}"; msize="${gmono##* }"
qfont="$gfam,$gsize,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
qmono="$mfam,$msize,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"

# --- 4. patch qt6ct.conf in place ------------------------------------------
if [[ -f "$QT6CT" ]]; then
    sed -i \
        -e "s|^color_scheme_path=.*|color_scheme_path=$SCHEME_FILE|" \
        -e "s|^custom_palette=.*|custom_palette=true|" \
        -e "s|^style=.*|style=Fusion|" \
        -e "s|^icon_theme=.*|icon_theme=$ICON_THEME|" \
        -e "s|^general=.*|general=\"$qfont\"|" \
        -e "s|^fixed=.*|fixed=\"$qmono\"|" \
        "$QT6CT"
fi

# --- 5. nudge already-running KDE/Qt apps to reload (best-effort) -----------
if command -v dbus-send >/dev/null 2>&1; then
    for t in 2 5 0; do
        dbus-send --session --type=signal /KGlobalSettings \
            org.kde.KGlobalSettings.notifyChange int32:$t int32:0 2>/dev/null || true
    done
fi

echo "✓ KDE color scheme : $SCHEME_FILE"
echo "✓ kdeglobals       : $KDEGLOBALS  (Fusion, icons=$ICON_THEME)"
echo "✓ qt6ct fonts      : $gfam $gsize / $mfam $msize"
GENEOF
chmod +x "$GEN"

# ----------------------------------------------------------------------------
# 5. Wire the generator into the Omarchy theme-set hook
# ----------------------------------------------------------------------------
info "Wiring generator into theme-set hook ($HOOKS/theme-set)"
mkdir -p "$HOOKS"
HOOK="$HOOKS/theme-set"
[[ -f "$HOOK" ]] || printf '#!/bin/bash\n' > "$HOOK"
if ! grep -q 'gen-qt-theme.sh' "$HOOK"; then
    {
        echo ''
        echo '# Regenerate KDE/Qt theming (Dolphin, Kate, Gwenview) to match the new theme'
        echo '"$HOME/.config/omarchy/scripts/gen-qt-theme.sh" >/dev/null 2>&1 || true'
    } >> "$HOOK"
fi
chmod +x "$HOOK"

# ----------------------------------------------------------------------------
# 6. Generate once for the current theme
# ----------------------------------------------------------------------------
info "Generating theming for the current Omarchy theme..."
"$GEN"

info "Done. Log out/in (or restart KDE apps) so Fusion + the new env apply everywhere."
