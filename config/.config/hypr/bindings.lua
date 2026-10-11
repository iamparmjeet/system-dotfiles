-- Application bindings.
-- Omarchy loads its application bindings before this file.  Remove the
-- defaults that this personal list replaces so one shortcut starts one app.
local personal_application_bindings = {

  "SUPER + CTRL + SHIFT + F",
  "SUPER + SHIFT + M",
  "SUPER + SHIFT + A",
  "SUPER + SHIFT + CTRL + A",
  "SUPER + CTRL + A",
  "SUPER + SHIFT + C",
  "SUPER + SHIFT + E",
  "SUPER + SHIFT + ALT + E",
  "SUPER + SHIFT + Y",
  "SUPER + SHIFT + ALT + G",
  "SUPER + SHIFT + CTRL + G",
  "SUPER + SHIFT + P",
  "SUPER + SHIFT + S",
  "SUPER + SHIFT + R",
  "SUPER + SHIFT + X",
  "SUPER + SHIFT + ALT + X",
}

for _, binding in ipairs(personal_application_bindings) do
  hl.unbind(binding)
end


o.bind("SUPER + SHIFT + M", "Music", "mpv --player-operation-mode=pseudo-gui --shuffle ~/Videos")
o.bind("SUPER + SHIFT + K", "Kate", { launch = "kate" })
o.bind("SUPER + ALT + D", "Lexicon", os.getenv("HOME") .. "/.config/omarchy/plugins/panadestein.lexicon/lexicon")

-- Open the System menu through its explicit alias. The literal "system"
-- route is shadowed by OpenSnitch's "system" desktop-entry keyword.
hl.unbind("SUPER + ESCAPE")
o.bind("SUPER + ESCAPE", "System menu", "omarchy-menu toggle power-menu")

-- Web app bindings.
local zen = "/opt/zen-browser-bin/zen-bin"
local web_ai = "~/.config/omarchy/scripts/web-ai-scratchpad "
o.bind("SUPER + SHIFT + A", "ChatGPT", web_ai .. "toggle chatgpt")
o.bind("SUPER + SHIFT + CTRL + A", "Claude", web_ai .. "toggle claude")
o.bind("SUPER + CTRL + A", "Web AI", "omarchy-shell shell toggle local.web-ai '{}'")
o.bind("SUPER + SHIFT + R", "Remnote", { launch = zen .. " --new-window https://remnote.com" })
o.bind("SUPER + SHIFT + C", "Calendar", { launch = zen .. " --new-window https://calendar.google.com/calendar/weeks/" })
o.bind("SUPER + SHIFT + E", "Email", { launch = zen .. " --new-window https://gmail.com" })
o.bind("SUPER + SHIFT + ALT + E", "New email",
    { launch = zen .. " --new-window https://app.gmail.com/messages/new?display=standalone&new_window=true" })
o.bind("SUPER + SHIFT + Y", "YouTube", { launch = zen .. " --new-window https://youtube.com/" })
o.bind("SUPER + SHIFT + ALT + G", "WhatsApp", { launch = zen .. " --new-window https://web.whatsapp.com/" })
o.bind(
    "SUPER + SHIFT + CTRL + G",
    "Google Messages",
    { launch = zen .. " --new-window https://messages.google.com/web/conversations" }
)
o.bind("SUPER + SHIFT + P", "Google Photos", { launch = zen .. " --new-window https://photos.google.com/" })
o.bind("SUPER + SHIFT + S", "Google Maps", { launch = zen .. " --new-window https://maps.google.com/" })
o.bind("SUPER + SHIFT + X", "X", { launch = zen .. " --new-window https://x.com/" })
o.bind("SUPER + SHIFT + ALT + X", "X Post", { launch = zen .. " --new-window https://x.com/compose/post" })

-- Add extra bindings below.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Keep Omarchy's transcoder usable with large media libraries. The stock
-- picker exceeds ARG_MAX because it passes every media path as a Perl argument.
hl.unbind("SUPER + CTRL + PERIOD")
o.bind(
    "SUPER + CTRL + PERIOD",
    "Transcode",
    'env PATH="$HOME/.config/omarchy/scripts:$PATH" omarchy-transcode'
)

-- Brightness follows the currently focused display. External monitors use
-- DDC/CI; the laptop panel falls back to its normal hardware backlight.
local focused_brightness_bindings = {
  "XF86MonBrightnessUp",
  "XF86MonBrightnessDown",
  "SHIFT + XF86MonBrightnessUp",
  "SHIFT + XF86MonBrightnessDown",
  "ALT + XF86MonBrightnessUp",
  "ALT + XF86MonBrightnessDown",
}

for _, binding in ipairs(focused_brightness_bindings) do
  hl.unbind(binding)
end

local focused_brightness = "~/.config/omarchy/scripts/brightness-focused-display "
o.bind("XF86MonBrightnessUp", "Brightness up", focused_brightness .. "+5%", { locked = true, repeating = true })
o.bind("XF86MonBrightnessDown", "Brightness down", focused_brightness .. "5%-", { locked = true, repeating = true })
o.bind("SHIFT + XF86MonBrightnessUp", "Brightness maximum", focused_brightness .. "100%", { locked = true, repeating = true })
o.bind("SHIFT + XF86MonBrightnessDown", "Brightness minimum", focused_brightness .. "1%", { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessUp", "Brightness up precise", focused_brightness .. "+1%", { locked = true, repeating = true })
o.bind("ALT + XF86MonBrightnessDown", "Brightness down precise", focused_brightness .. "1%-", { locked = true, repeating = true })

-- Theme menu: original 4-mod chord is kept, plus an easier 2-mod alias for keyboards that ghost
-- SUPER+SHIFT+CTRL+SPACE is defined in /usr/share/omarchy/default/hypr/bindings/utilities.lua:18
o.bind("SUPER + ALT + T", "Theme menu", "omarchy-menu toggle theme")

-- Overwrite existing bindings with hl.unbind() first if needed.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, { omarchy = "walker -m symbols" })
