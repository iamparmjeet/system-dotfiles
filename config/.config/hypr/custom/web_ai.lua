-- Clean-room Web AI scratchpad rules.
--
-- The address-targeted controller remains authoritative. These rules are a
-- fast path for browser app windows that honor their requested class.

local config_path = (os.getenv("HOME") or "") .. "/.config/omarchy/web-ai.json"
local width_ratio = 0.32
local height_ratio = 0.9
local edge_gap = 18

local config_file = io.open(config_path, "r")
if config_file then
  local raw = config_file:read("*a")
  config_file:close()
  local panel = raw:match('"panel"%s*:%s*{(.-)}')
  if panel then
    local configured_width = tonumber(panel:match('"widthRatio"%s*:%s*([%d%.]+)'))
    local configured_height = tonumber(panel:match('"heightRatio"%s*:%s*([%d%.]+)'))
    local configured_gap = tonumber(panel:match('"edgeGap"%s*:%s*([%d%.]+)'))

    if configured_width and configured_width > 0 and configured_width <= 1 then
      width_ratio = configured_width
    end
    if configured_height and configured_height > 0 and configured_height <= 1 then
      height_ratio = configured_height
    end
    if configured_gap and configured_gap >= 0 then
      edge_gap = configured_gap
    end
  end
end

local width_expression = string.format("monitor_w * %.10g", width_ratio)
local height_expression = string.format("monitor_h * %.10g", height_ratio)
local x_expression = string.format("%.10g", edge_gap)
local y_expression = "(monitor_h - window_h) * 0.5"

local providers = {
  {
    id = "chatgpt",
    class = "local-web-ai-chatgpt",
    workspace = "web-ai-chatgpt",
  },
  {
    id = "claude",
    class = "local-web-ai-claude",
    workspace = "web-ai-claude",
  },
}

for _, provider in ipairs(providers) do
  hl.workspace_rule({
    workspace = "special:" .. provider.workspace,
    persistent = true,
  })

  hl.window_rule({
    name = "local-web-ai-" .. provider.id,
    match = { class = provider.class },
    float = true,
    workspace = "special:" .. provider.workspace .. " silent",
    size = { width_expression, height_expression },
    move = { x_expression, y_expression },
    persistent_size = true,
  })
end
