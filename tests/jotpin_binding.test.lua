local binding_path = assert(arg[1], "binding path is required")

local normal_workspace = { id = 1, name = "1" }
local special_workspace = { id = -96, name = "special:scratchpad" }
local visible_workspace = special_workspace
local jotpin_window = {
  address = "abc123",
  title = "JotPin Side top right — welcome.md",
  workspace = normal_workspace,
}
local windows = { jotpin_window }
local dispatches = {}
local timers = {}
local bound_callback = nil

local function reset_dispatches()
  dispatches = {}
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error(message .. ": expected " .. tostring(expected) ..
      ", got " .. tostring(actual), 2)
  end
  print("PASS: " .. message)
end

hl = {
  get_active_special_workspace = function()
    return visible_workspace and visible_workspace.id < 0
      and visible_workspace or nil
  end,
  get_active_workspace = function()
    return visible_workspace and visible_workspace.id > 0
      and visible_workspace or normal_workspace
  end,
  get_windows = function()
    return windows
  end,
  dispatch = function(dispatcher)
    table.insert(dispatches, dispatcher)
  end,
  timer = function(callback, options)
    table.insert(timers, { callback = callback, options = options })
    return {
      is_enabled = function() return true end,
      set_enabled = function() end,
      set_timeout = function() end,
    }
  end,
  dsp = {
    exec_cmd = function(command)
      return { kind = "exec", command = command }
    end,
    focus = function(spec)
      return { kind = "focus", spec = spec }
    end,
    window = {
      move = function(spec)
        return { kind = "move", spec = spec }
      end,
    },
  },
}

o = {
  bind = function(key, description, callback)
    assert_equal(key, "SUPER + N", "the binding keeps the default shortcut")
    assert_equal(description, "Markdown scratchpad",
      "the binding keeps its menu description")
    bound_callback = callback
  end,
}

dofile(binding_path)
assert(bound_callback, "the binding callback was not registered")
assert_equal(bound_callback, jotpin_toggle_markdown_scratchpad,
  "the bound callback remains directly callable for compositor validation")

bound_callback()
assert_equal(#dispatches, 1, "cross-workspace summon dispatches only the move")
assert_equal(dispatches[1].kind, "move",
  "cross-workspace summon moves the existing JotPin window")
assert_equal(dispatches[1].spec.workspace, "special:scratchpad",
  "a special destination is dispatched by its explicit workspace selector")
assert_equal(#timers, 1, "cross-workspace focus waits for compositor state")

local first_timer = table.remove(timers, 1)
first_timer.callback()
assert_equal(#dispatches, 1,
  "JotPin is not focused while its old workspace is still reported")
assert_equal(#timers, 1,
  "the binding retries while the compositor move is still pending")

jotpin_window.workspace = special_workspace
local second_timer = table.remove(timers, 1)
second_timer.callback()
assert_equal(#dispatches, 2,
  "JotPin is focused after reaching the visible special workspace")
assert_equal(dispatches[2].kind, "focus",
  "the post-move action is compositor focus")
assert_equal(dispatches[2].spec.window, jotpin_window,
  "the relocated live window object receives focus")

reset_dispatches()
bound_callback()
assert_equal(#dispatches, 1,
  "same-workspace toggle emits one shell action")
assert_equal(dispatches[1].kind, "exec",
  "same-workspace toggle delegates hiding to the shell")
assert_equal(dispatches[1].command, "omarchy-shell shell hide dev.jotpin",
  "same-workspace toggle hides JotPin")

reset_dispatches()
windows = {}
bound_callback()
assert_equal(#dispatches, 1, "closed JotPin emits one shell action")
assert_equal(dispatches[1].command,
  "omarchy-shell shell summon dev.jotpin",
  "closed JotPin is summoned")

reset_dispatches()
windows = { jotpin_window }
jotpin_window.workspace = normal_workspace
visible_workspace = special_workspace
bound_callback()
assert_equal(dispatches[1].kind, "move",
  "a second cross-workspace summon starts another move")
visible_workspace = normal_workspace
local abandoned_timer = table.remove(timers, 1)
abandoned_timer.callback()
assert_equal(#dispatches, 1,
  "a workspace change during relocation cancels stale focus")
assert_equal(#timers, 0,
  "a canceled relocation does not keep polling")

reset_dispatches()
visible_workspace = special_workspace
jotpin_window.workspace = normal_workspace
bound_callback()
local hide_race_timer = table.remove(timers, 1)
jotpin_window.workspace = special_workspace
bound_callback()
assert_equal(dispatches[#dispatches].command,
  "omarchy-shell shell hide dev.jotpin",
  "a second press hides JotPin after the move reaches its workspace")
local dispatch_count_after_hide = #dispatches
hide_race_timer.callback()
assert_equal(#dispatches, dispatch_count_after_hide,
  "a superseded relocation timer cannot refocus a hidden JotPin")
