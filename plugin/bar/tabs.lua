local utilities = require "bar.utilities"

---@private
---@class bar.tabs
local M = {}

---@class tabs.tabinfo
---@field tab_title string
---@field active_pane table
---@field active_pane.title string

---get tab title
---@param tab_info tabs.tabinfo
---@return string
M.get_title = function(tab_info)
  local title = tab_info.tab_title
  -- if the tab title is explicitly set, take that
  if title and #title > 0 then
    return title
  end
  -- Otherwise, use the title from the active pane
  -- in that tab
  return utilities._basename(tab_info.active_pane.title)
end

---get cwd for tab's active pane
---@param tab_info tabs.tabinfo
---@return string
M.get_cwd = function(tab_info)
  local pane = tab_info.active_pane
  local cwd = ""
  local cwd_uri = pane.current_working_dir
  if cwd_uri then
    if type(cwd_uri) == "userdata" then
      ---@diagnostic disable-next-line: undefined-field
      cwd = cwd_uri.file_path
    else
      cwd_uri = cwd_uri:sub(8)
      local slash = cwd_uri:find "/"
      if slash then
        cwd = cwd_uri:sub(slash):gsub("%%(%x%x)", function(hex)
          return string.char(tonumber(hex, 16))
        end)
      end
    end
    -- Replace home with ~
    cwd = cwd:gsub(utilities.home .. "/?", "~/")
    -- Get just the last directory name
    cwd = cwd:match("([^/]+)/?$") or cwd
  end
  return cwd
end

return M
