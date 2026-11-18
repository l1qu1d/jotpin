-- Both JotPin presentations remain xdg toplevels so Hyprland's normal
-- fullscreen, maximize, restore, move, and resize actions work without
-- JotPin duplicating user keybindings. Their distinct initial titles let
-- Hyprland apply the correct static placement rule when each window maps.
-- Names let JotPin re-register these rules before each map without stacking
-- duplicate rules in the compositor.
hl.window_rule({
  name = "dev-jotpin-center",
  match = {
    class = "^org\\.quickshell$",
    title = "^JotPin Window — .+$",
  },
  float = true,
  center = true,
})

hl.window_rule({
  name = "dev-jotpin-side",
  match = {
    class = "^org\\.quickshell$",
    title = "^JotPin Side (top|bottom|left|right) (left|right) — .+$",
  },
  float = true,
  border_size = 0,
  no_shadow = true,
})

-- A top bar reserves vertical work area above Side. The window's QML height
-- already excludes that strip, so bottom-aligning places it immediately below
-- the bar instead of mapping it behind the layer-shell surface.
hl.window_rule({
  name = "dev-jotpin-top-left",
  match = {
    class = "^org\\.quickshell$",
    title = "^JotPin Side top left — .+$",
  },
  move = { "0", "monitor_h-window_h" },
})

hl.window_rule({
  name = "dev-jotpin-top-right",
  match = {
    class = "^org\\.quickshell$",
    title = "^JotPin Side top right — .+$",
  },
  move = { "monitor_w-window_w", "monitor_h-window_h" },
})

hl.window_rule({
  name = "dev-jotpin-left",
  match = {
    class = "^org\\.quickshell$",
    title = "^JotPin Side (bottom|left|right) left — .+$",
  },
  move = { "0", "0" },
})

hl.window_rule({
  name = "dev-jotpin-right",
  match = {
    class = "^org\\.quickshell$",
    title = "^JotPin Side (bottom|left|right) right — .+$",
  },
  move = { "monitor_w-window_w", "0" },
})
