local log = require("log")

local M = {}

local SyntaxPicker = {}
SyntaxPicker.__index = SyntaxPicker

local function escape_html(str)
    if not str then return "" end
    local map = {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
    }
    return (str:gsub("[&<>\"']", map))
end

function SyntaxPicker:escape(str)
    return escape_html(str)
end

function SyntaxPicker:keyword(str)
    return string.format("<span class='%s'>%s</span>", self.classes.keyword, escape_html(str))
end

function SyntaxPicker:type(str, href)
    local escaped = escape_html(str)
    if href and href ~= "" then
        return string.format("<a class='%s' href='%s'>%s</a>", self.classes.type, href, escaped)
    end
    return string.format("<span class='%s'>%s</span>", self.classes.type, escaped)
end

function SyntaxPicker:function_name(str)
    return string.format("<span class='%s'>%s</span>", self.classes.function_name, escape_html(str))
end

function SyntaxPicker:literal(str)
    return string.format("<span class='%s'>%s</span>", self.classes.literal, escape_html(str))
end

function SyntaxPicker:comment(str)
    return string.format("<span class='%s'>%s</span>", self.classes.comment, escape_html(str))
end

function SyntaxPicker:attribute(str)
    return string.format("<span class='%s'>%s</span>", self.classes.attribute, escape_html(str))
end

--- Creates a new SyntaxPicker instance with optional custom class names (Dependency Injection).
function M.create(options)
    options = options or {}
    local self = setmetatable({}, SyntaxPicker)
    self.classes = {
        keyword = options.kw_class or "kw",
        type = options.type_class or "type",
        function_name = options.fn_class or "fn",
        literal = options.lit_class or "lit",
        comment = options.comment_class or "comment",
        attribute = options.attr_class or "attr",
    }
    log.debug("Instantiated SyntaxPicker.")
    return self
end

return M
