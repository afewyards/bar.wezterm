local wez = require "wezterm"

---@class bar.wezterm
local M = {}
local options = {}

local separator = package.config:sub(1, 1) == "\\" and "\\" or "/"

-- Find this plugin's directory (bar.wezterm encoded as barsDswezterm)
local function get_plugin_dir()
  for _, plugin in ipairs(wez.plugin.list()) do
    if plugin.plugin_dir:find("barsDswezterm") then
      return plugin.plugin_dir
    end
  end
  return wez.plugin.list()[1].plugin_dir
end

local plugin_dir = get_plugin_dir()

package.path = package.path
  .. ";"
  .. plugin_dir
  .. separator
  .. "plugin"
  .. separator
  .. "?.lua"

local utilities = require "bar.utilities"
local config = require "bar.config"
local tabs = require "bar.tabs"
local user = require "bar.user"
local spotify = require "bar.spotify"
local paths = require "bar.paths"

---get battery info with appropriate icon
---@return string, string
local function get_battery()
  local battery_info = wez.battery_info()
  if #battery_info > 0 then
    local charge = battery_info[1].state_of_charge * 100
    local icon = wez.nerdfonts.fa_battery_full
    if charge < 10 then
      icon = wez.nerdfonts.fa_battery_empty
    elseif charge < 35 then
      icon = wez.nerdfonts.fa_battery_quarter
    elseif charge < 65 then
      icon = wez.nerdfonts.fa_battery_half
    elseif charge < 90 then
      icon = wez.nerdfonts.fa_battery_three_quarters
    end
    return string.format('%.0f%%', charge), icon
  end
  return "", wez.nerdfonts.fa_battery_full
end

---conforming to https://github.com/wez/wezterm/commit/e4ae8a844d8feaa43e1de34c5cc8b4f07ce525dd
---@param c table: wezterm config object
---@param opts bar.options
M.apply_to_config = function(c, opts)
  -- make the opts arg optional
  if not opts then
    ---@diagnostic disable-next-line: missing-fields
    opts = {}
  end

  -- combine user config with defaults
  options = config.extend_options(config.options, opts)

  local scheme = wez.color.get_builtin_schemes()[c.color_scheme]
  if scheme ~= nil then
    if c.colors ~= nil then
      scheme = utilities._merge(scheme, c.colors)
    end
    local default_colors = {
      tab_bar = {
        background = "transparent",
        active_tab = {
          bg_color = "transparent",
          fg_color = scheme.ansi[options.modules.tabs.active_tab_fg],
        },
        inactive_tab = {
          bg_color = "transparent",
          fg_color = scheme.ansi[options.modules.tabs.inactive_tab_fg],
        },
        new_tab = {
          bg_color = "transparent",
          fg_color = scheme.ansi[options.modules.tabs.new_tab_fg],
        },
      },
    }
    c.colors = utilities._merge(default_colors, scheme)
  end

  -- make the plugin own these settings
  c.tab_bar_at_bottom = options.position == "bottom"
  c.use_fancy_tab_bar = false
  c.tab_max_width = options.max_width
end

wez.on("format-tab-title", function(tab, _, _, conf, _, _)
  local palette = conf.resolved_palette

  local index = tab.tab_index + 1
  local title_part = tabs.get_title(tab)

  -- Add cwd if enabled
  if options.modules.tabs.show_cwd then
    local cwd = tabs.get_cwd(tab)
    if cwd and #cwd > 0 then
      title_part = title_part .. " " .. cwd
    end
  end

  local offset = #tostring(index) + #options.separator.left_icon + (2 * options.separator.space) + 2
  local title = index
    .. utilities._space(options.separator.left_icon, options.separator.space, nil)
    .. title_part

  local width = conf.tab_max_width - offset
  if #title > conf.tab_max_width then
    title = wez.truncate_right(title, width) .. "…"
  end

  local fg = palette.tab_bar.inactive_tab.fg_color
  local bg = palette.tab_bar.inactive_tab.bg_color
  if tab.is_active then
    fg = palette.tab_bar.active_tab.fg_color
    bg = palette.tab_bar.active_tab.bg_color
  end

  return {
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = utilities._space(title, options.padding.tabs.left, options.padding.tabs.right) },
  }
end)

wez.on("update-status", function(window, pane)
  local present, conf = pcall(window.effective_config, window)
  if not present then
    return
  end

  local palette = conf.resolved_palette

  -- left status
  local left_cells = {
    { Background = { Color = palette.tab_bar.background } },
  }

  table.insert(left_cells, { Text = string.rep(" ", options.padding.left) })

  if options.modules.workspace.enabled then
    local stat = options.modules.workspace.icon .. utilities._space(window:active_workspace(), options.separator.space)
    local stat_fg = palette.ansi[options.modules.workspace.color]

    if options.modules.leader.enabled and window:leader_is_active() then
      stat_fg = palette.ansi[options.modules.leader.color]
      stat = utilities._constant_width(stat, options.modules.leader.icon)
    end

    table.insert(left_cells, { Foreground = { Color = stat_fg } })
    table.insert(left_cells, { Text = stat })
  end

  if options.modules.zoom.enabled and pane:tab() then
    local panes_with_info = pane:tab():panes_with_info()
    for _, p in ipairs(panes_with_info) do
      if p.is_active and p.is_zoomed then
        table.insert(left_cells, { Foreground = { Color = palette.ansi[options.modules.zoom.color] } })
        table.insert(
          left_cells,
          { Text = options.modules.zoom.icon .. utilities._space("zoom", options.separator.space) }
        )
      end
    end
  end

  if options.modules.pane.enabled then
    local process = pane:get_foreground_process_name()
    if not process then
      goto set_left_status
    end
    table.insert(left_cells, { Foreground = { Color = palette.ansi[options.modules.pane.color] } })
    table.insert(
      left_cells,
      { Text = options.modules.pane.icon .. utilities._space(utilities._basename(process), options.separator.space) }
    )
  end

  ::set_left_status::
  window:set_left_status(wez.format(left_cells))

  -- right status
  local right_cells = {
    { Background = { Color = palette.tab_bar.background } },
  }

  local callbacks = {
    {
      name = "spotify",
      func = function()
        return spotify.get_currently_playing(options.modules.spotify.max_width, options.modules.spotify.throttle)
      end,
      get_icon = function() return options.modules.spotify.icon end,
    },
    {
      name = "username",
      func = function()
        return user.username
      end,
      get_icon = function() return options.modules.username.icon end,
    },
    {
      name = "hostname",
      func = function()
        return wez.hostname()
      end,
      get_icon = function() return options.modules.hostname.icon end,
    },
    {
      name = "clock",
      func = function()
        return wez.time.now():format(options.modules.clock.format)
      end,
      get_icon = function() return options.modules.clock.icon end,
    },
    {
      name = "cwd",
      func = function()
        return paths.get_cwd(pane, true)
      end,
      get_icon = function() return options.modules.cwd.icon end,
    },
    {
      name = "battery",
      func = function()
        local charge, _ = get_battery()
        return charge
      end,
      get_icon = function()
        local _, icon = get_battery()
        return icon
      end,
    },
  }

  for _, callback in ipairs(callbacks) do
    local name = callback.name
    local func = callback.func
    if not options.modules[name].enabled then
      goto continue
    end
    local text = func()
    if #text > 0 then
      local icon_spacing = string.rep(" ", options.separator.icon_space)
      local icon = callback.get_icon()

      if options.separator.icon_position == "left" then
        -- Icon before text: "🕐  Wed 14:30"
        table.insert(right_cells, { Foreground = { Color = palette.ansi[options.modules[name].color] } })
        table.insert(right_cells, { Text = icon .. icon_spacing .. text })
      else
        -- Icon after text (default): "Wed 14:30 🕐"
        table.insert(right_cells, { Foreground = { Color = palette.ansi[options.modules[name].color] } })
        table.insert(right_cells, { Text = text })
        table.insert(right_cells, { Foreground = { Color = palette.brights[1] } })
        table.insert(right_cells, {
          Text = utilities._space(options.separator.right_icon, options.separator.space, nil)
            .. icon_spacing .. icon .. icon_spacing,
        })
      end
      table.insert(right_cells, { Text = utilities._space(options.separator.field_icon, options.separator.space, nil) })
    end
    ::continue::
  end
  -- remove trailing separator
  table.remove(right_cells, #right_cells)
  table.insert(right_cells, { Text = string.rep(" ", options.padding.right) })

  window:set_right_status(wez.format(right_cells))
end)

return M
