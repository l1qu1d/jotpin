-- Optional default shortcut installed only when SUPER + N is free.
-- Keep this in the user's bindings load path so it remains an ordinary,
-- update-safe Hyprland override that can be edited or removed independently.
local relocation_generation = 0

-- Keep a namespaced handle in Hyprland's Lua state so the exact callback can
-- be exercised through `hyprctl eval` during compositor validation.
function jotpin_toggle_markdown_scratchpad()
  relocation_generation = relocation_generation + 1
  local generation = relocation_generation
  local active_workspace = hl.get_active_special_workspace() or
    hl.get_active_workspace()
  if not active_workspace then return end

  local jotpin_window = nil
  for _, window in pairs(hl.get_windows()) do
    local title = window.title or ""
    if title:match("^JotPin Side ") or title:match("^JotPin Window — ") then
      jotpin_window = window
      break
    end
  end

  if not jotpin_window then
    hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell summon dev.jotpin"))
    return
  end

  if jotpin_window.workspace and
      jotpin_window.workspace.id == active_workspace.id then
    hl.dispatch(hl.dsp.exec_cmd("omarchy-shell shell hide dev.jotpin"))
    return
  end

  -- Hyprland applies dispatcher changes after the Lua callback returns. If the
  -- old workspace is focused immediately, it can win that race and hide the
  -- special workspace we are moving JotPin into. Poll the live window model
  -- briefly and focus only after the compositor reports the destination.
  local target_id = active_workspace.id
  local target_name = active_workspace.name
  local target_selector = tostring(target_name or "")
  if not active_workspace.special and
      not target_selector:match("^special:") then
    if type(target_id) == "number" and target_id > 0 and
        target_name == tostring(target_id) then
      target_selector = tostring(target_id)
    else
      target_selector = "name:" .. tostring(target_name)
    end
  end
  local window_address = jotpin_window.address
  local attempts = 0

  local function same_workspace(workspace)
    if not workspace then return false end
    if workspace.id ~= nil and target_id ~= nil then
      return workspace.id == target_id
    end
    return workspace.name ~= nil and target_name ~= nil and
      workspace.name == target_name
  end

  local function focus_after_move()
    if generation ~= relocation_generation then return end
    local visible_workspace = hl.get_active_special_workspace() or
      hl.get_active_workspace()
    if not same_workspace(visible_workspace) then return end

    local moved_window = nil
    for _, window in pairs(hl.get_windows()) do
      if window.address == window_address then
        moved_window = window
        break
      end
    end

    if moved_window and same_workspace(moved_window.workspace) then
      hl.dispatch(hl.dsp.focus({ window = moved_window }))
      return
    end

    attempts = attempts + 1
    if attempts < 20 then
      hl.timer(focus_after_move, { timeout = 25, type = "oneshot" })
    end
  end

  hl.dispatch(hl.dsp.window.move({
    workspace = target_selector,
    follow = false,
    window = jotpin_window,
  }))
  hl.timer(focus_after_move, { timeout = 25, type = "oneshot" })
end

o.bind("SUPER + N", "Markdown scratchpad",
  jotpin_toggle_markdown_scratchpad)
