-- Both JotPin presentations remain xdg toplevels so Hyprland's normal
-- fullscreen, maximize, restore, move, and resize actions work without
-- JotPin duplicating user keybindings. Their distinct initial titles let
-- Hyprland apply the correct static placement rule when each window maps.
o.window({
  class = "^org\\.quickshell$",
  title = "^JotPin Window — .+$",
}, {
  float = true,
  center = true,
})

o.window({
  class = "^org\\.quickshell$",
  title = "^JotPin Side (top|bottom|left|right) (left|right) — .+$",
}, {
  float = true,
  border_size = 0,
  no_shadow = true,
})

-- A top bar reserves vertical work area above Side. The window's QML height
-- already excludes that strip, so bottom-aligning places it immediately below
-- the bar instead of mapping it behind the layer-shell surface.
o.window({
  class = "^org\\.quickshell$",
  title = "^JotPin Side top left — .+$",
}, {
  move = { "0", "monitor_h-window_h" },
})

o.window({
  class = "^org\\.quickshell$",
  title = "^JotPin Side top right — .+$",
}, {
  move = { "monitor_w-window_w", "monitor_h-window_h" },
})

o.window({
  class = "^org\\.quickshell$",
  title = "^JotPin Side (bottom|left|right) left — .+$",
}, {
  move = { "0", "0" },
})

o.window({
  class = "^org\\.quickshell$",
  title = "^JotPin Side (bottom|left|right) right — .+$",
}, {
  move = { "monitor_w-window_w", "0" },
})
