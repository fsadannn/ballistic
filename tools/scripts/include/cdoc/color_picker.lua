local log = require("log")

local M = {}

local THEMES = {
    dark = {
        ["--bg"] = "#0f1419",
        ["--sidebar-bg"] = "#14191f",
        ["--text"] = "#c5c5c5",
        ["--header-text"] = "#ffffff",
        ["--link"] = "#39afd7",
        ["--code-bg"] = "#191f26",
        ["--border"] = "#252c37",
        ["--sidebar-hover"] = "#1e252e",
        ["--sidebar-text"] = "#c5c5c5",
        ["--kw-color"] = "#ff7b72",
        ["--type-color"] = "#79c0ff",
        ["--fn-color"] = "#d2a8ff",
        ["--lit-color"] = "#a5d6ff",
        ["--comment-color"] = "#8b949e",
        ["--attr-color"] = "#7ee787",
        ["--badge-bg"] = "#21262d",
        ["--badge-text"] = "#8b949e",
        ["--callout-bg"] = "rgba(57, 175, 215, 0.1)",
        ["--callout-border"] = "#39afd7",
        ["--callout-safety-bg"] = "rgba(248, 81, 73, 0.12)",
        ["--callout-safety-border"] = "#f85149",
        ["--callout-error-bg"] = "rgba(240, 136, 62, 0.12)",
        ["--callout-error-border"] = "#f0883e",
    },
    light = {
        ["--bg"] = "#ffffff",
        ["--sidebar-bg"] = "#f5f5f5",
        ["--text"] = "#333333",
        ["--header-text"] = "#000000",
        ["--link"] = "#3873ad",
        ["--code-bg"] = "#f7f7f7",
        ["--border"] = "#e0e0e0",
        ["--sidebar-hover"] = "#e8e8e8",
        ["--sidebar-text"] = "#333333",
        ["--kw-color"] = "#8959a8",
        ["--type-color"] = "#4271ae",
        ["--fn-color"] = "#c82829",
        ["--lit-color"] = "#718c00",
        ["--comment-color"] = "#8e908c",
        ["--attr-color"] = "#3e999f",
        ["--badge-bg"] = "#eaeaea",
        ["--badge-text"] = "#555555",
        ["--callout-bg"] = "rgba(56, 115, 173, 0.08)",
        ["--callout-border"] = "#3873ad",
        ["--callout-safety-bg"] = "rgba(211, 47, 47, 0.08)",
        ["--callout-safety-border"] = "#d32f2f",
        ["--callout-error-bg"] = "rgba(245, 124, 0, 0.08)",
        ["--callout-error-border"] = "#f57c00",
    },
    ayu = {
        ["--bg"] = "#0f141c",
        ["--sidebar-bg"] = "#141922",
        ["--text"] = "#c5c5c5",
        ["--header-text"] = "#ffffff",
        ["--link"] = "#39afd7",
        ["--code-bg"] = "#191f2b",
        ["--border"] = "#252c3c",
        ["--sidebar-hover"] = "#1e2536",
        ["--sidebar-text"] = "#c5c5c5",
        ["--kw-color"] = "#ff7733",
        ["--type-color"] = "#55b4d4",
        ["--fn-color"] = "#f29718",
        ["--lit-color"] = "#e6b450",
        ["--comment-color"] = "#707a8c",
        ["--attr-color"] = "#a6e22e",
        ["--badge-bg"] = "#1d222e",
        ["--badge-text"] = "#707a8c",
        ["--callout-bg"] = "rgba(85, 180, 212, 0.1)",
        ["--callout-border"] = "#55b4d4",
        ["--callout-safety-bg"] = "rgba(255, 119, 51, 0.12)",
        ["--callout-safety-border"] = "#ff7733",
        ["--callout-error-bg"] = "rgba(242, 151, 24, 0.12)",
        ["--callout-error-border"] = "#f29718",
    },
}

local ColorPicker = {}
ColorPicker.__index = ColorPicker

function ColorPicker:theme_name()
    return self._name
end

function ColorPicker:get_color(name)
    return self._colors[name] or "#ffffff"
end

function ColorPicker:get_css_variables()
    local lines = { ":root {" }
    for k, v in pairs(self._colors) do
        table.insert(lines, string.format("    %s: %s;", k, v))
    end
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

--- Creates a new ColorPicker instance (Dependency Injection).
function M.create(name)
    name = (name and THEMES[name:lower()]) and name:lower() or "dark"
    log.debug("Instantiating ColorPicker with theme '%s'.", name)

    local self = setmetatable({}, ColorPicker)
    self._name = name
    self._colors = THEMES[name]
    return self
end

return M
