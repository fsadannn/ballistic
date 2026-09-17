local log = require("log")
local ast = require("ast")
local color_picker = require("color_picker")
local syntax_picker = require("syntax_picker")
local page_structure = require("page_structure")

local M = {}

local Generator = {}
Generator.__index = Generator

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

--- Lightweight Markdown subset renderer for pure Lua
function Generator:render_markdown(raw_text, current_file)
    if not raw_text or raw_text == "" then
        return ""
    end

    -- 1. Extract and preserve code blocks
    local code_blocks = {}
    local text = raw_text:gsub("```(.-)\n(.-)```", function(lang, code)
        local id = string.format("@@CODEBLOCK_%d@@", #code_blocks + 1)
        table.insert(code_blocks, string.format("<pre><code>%s</code></pre>", escape_html(code)))
        return id
    end)

    -- 2. Resolve [`SYMBOL`] references to standard markdown links [SYMBOL](url)
    text = text:gsub("%[`([^`]+)`%]", function(sym)
        local target = self:find_link_target(sym)
        if target then
            if target.file == current_file then
                return string.format("[%s](#%s)", sym, target.anchor)
            else
                return string.format("[%s](%s.html#%s)", sym, target.file, target.anchor)
            end
        end
        return string.format("`%s`", sym)
    end)

    -- 3. Line by line processing for blocks (headings, lists, paragraphs)
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local out = {}
    local in_list = false
    local list_type = nil -- "ul" or "ol"
    local p_lines = {}

    local function flush_p()
        if #p_lines > 0 then
            local p_text = table.concat(p_lines, " ")
            table.insert(out, string.format("<p>%s</p>", self:render_inline(p_text)))
            p_lines = {}
        end
    end

    local function close_list()
        if in_list then
            table.insert(out, string.format("</%s>", list_type))
            in_list = false
            list_type = nil
        end
    end

    for _, line in ipairs(lines) do
        local trimmed = line:match("^%s*(.-)%s*$")

        if trimmed == "" then
            flush_p()
            close_list()
        elseif trimmed:match("^@@CODEBLOCK_%d+@@$") then
            flush_p()
            close_list()
            local idx = tonumber(trimmed:match("%d+"))
            table.insert(out, code_blocks[idx] or "")
        elseif trimmed:match("^###%s+(.*)$") then
            flush_p()
            close_list()
            local h = trimmed:match("^###%s+(.*)$")
            table.insert(out, string.format("<h3>%s</h3>", self:render_inline(h)))
        elseif trimmed:match("^##%s+(.*)$") then
            flush_p()
            close_list()
            local h = trimmed:match("^##%s+(.*)$")
            table.insert(out, string.format("<h2>%s</h2>", self:render_inline(h)))
        elseif trimmed:match("^#%s+(.*)$") then
            flush_p()
            close_list()
            local h = trimmed:match("^#%s+(.*)$")
            table.insert(out, string.format("<h1>%s</h1>", self:render_inline(h)))
        elseif trimmed:match("^[-%*]%s+(.*)$") then
            flush_p()
            local item = trimmed:match("^[-%*]%s+(.*)$")
            if not in_list or list_type ~= "ul" then
                close_list()
                in_list = true
                list_type = "ul"
                table.insert(out, "<ul>")
            end
            table.insert(out, string.format("<li>%s</li>", self:render_inline(item)))
        elseif trimmed:match("^%d+%.%s+(.*)$") then
            flush_p()
            local item = trimmed:match("^%d+%.%s+(.*)$")
            if not in_list or list_type ~= "ol" then
                close_list()
                in_list = true
                list_type = "ol"
                table.insert(out, "<ol>")
            end
            table.insert(out, string.format("<li>%s</li>", self:render_inline(item)))
        else
            close_list()
            table.insert(p_lines, trimmed)
        end
    end

    flush_p()
    close_list()

    return table.concat(out, "\n")
end

--- Formats inline text with markdown syntax (code, bold, italic, links)
function Generator:render_inline(text)
    if not text then return "" end

    -- Extract links [text](url)
    local links = {}
    text = text:gsub("%[([^%]]+)%]%(([^%)]+)%)", function(label, url)
        local id = string.format("@@LINK_%d@@", #links + 1)
        table.insert(links, string.format("<a href='%s'>%s</a>", escape_html(url), escape_html(label)))
        return id
    end)

    -- Extract inline code `code`
    local codes = {}
    text = text:gsub("`([^`]+)`", function(code)
        local id = string.format("@@CODE_%d@@", #codes + 1)
        table.insert(codes, string.format("<code>%s</code>", escape_html(code)))
        return id
    end)

    -- Escape remaining text
    text = escape_html(text)

    -- Bold **text**
    text = text:gsub("%*%*([^*]+)%*%*", "<strong>%1</strong>")

    -- Italic *text*
    text = text:gsub("%*([^*]+)%*", "<em>%1</em>")

    -- Restore codes
    text = text:gsub("@@CODE_(%d+)@@", function(i)
        return codes[tonumber(i)] or ""
    end)

    -- Restore links
    text = text:gsub("@@LINK_(%d+)@@", function(i)
        return links[tonumber(i)] or ""
    end)

    return text
end

function Generator:find_link_target(name)
    if not self.registry or not name then return nil end
    return self.registry:find(name)
end

--- Replaces words in C type definitions with links if found in registry
function Generator:linkify_type(raw_type, current_file)
    if not raw_type or raw_type == "" then
        return ""
    end

    local result = {}
    local i = 1
    local len = #raw_type

    while i <= len do
        local start_pos, end_pos, word = raw_type:find("([%a_][%w_]*)", i)
        if start_pos then
            if start_pos > i then
                local prefix = raw_type:sub(i, start_pos - 1)
                table.insert(result, self.syntax:escape(prefix))
            end

            local target = self:find_link_target(word)
            if target then
                local href = (target.file == current_file) and ("#" .. target.anchor) or (target.file .. ".html#" .. target.anchor)
                table.insert(result, self.syntax:type(word, href))
            else
                table.insert(result, self.syntax:type(word, nil))
            end
            i = end_pos + 1
        else
            local tail = raw_type:sub(i)
            table.insert(result, self.syntax:escape(tail))
            break
        end
    end

    return table.concat(result)
end

--- Renders a documentation structure (from documentation.lua)
function Generator:render_doc_block(doc, current_file)
    if not doc then return "" end

    local out = { "<div class='docblock'>" }

    if doc.summary and doc.summary ~= "" then
        table.insert(out, self:render_markdown(doc.summary, current_file))
    end

    if doc.sections then
        for _, sec in ipairs(doc.sections) do
            local sec_name_lower = sec.name:lower()
            local callout_class = "callout"
            if sec_name_lower == "safety" then
                callout_class = "callout safety"
            elseif sec_name_lower == "errors" or sec_name_lower == "warning" then
                callout_class = "callout errors"
            end

            table.insert(out, string.format("<div class='%s'>", callout_class))
            table.insert(out, string.format("<div class='callout-title'>%s</div>", escape_html(sec.name)))
            table.insert(out, self:render_markdown(sec.content, current_file))
            table.insert(out, "</div>")
        end
    end

    table.insert(out, "</div>")
    return table.concat(out, "\n")
end

--- Builds the docs.rs sidebar HTML for a specific module
function Generator:build_sidebar(module_node)
    local out = {}

    table.insert(out, "<a class='sidebar-back' href='index.html'>&larr; All Headers</a>")
    table.insert(out, string.format("<div class='sidebar-title'>%s</div>", escape_html(module_node.name)))

    local sections = {
        { kind = ast.KIND.STRUCT, title = "Structs" },
        { kind = ast.KIND.UNION, title = "Unions" },
        { kind = ast.KIND.ENUM, title = "Enums" },
        { kind = ast.KIND.FUNCTION, title = "Functions" },
        { kind = ast.KIND.TYPEDEF, title = "Type Aliases" },
    }

    for _, sec in ipairs(sections) do
        local matching = {}
        for _, item in ipairs(module_node.items) do
            if item.kind == sec.kind then
                table.insert(matching, item)
            end
        end

        if #matching > 0 then
            table.sort(matching, function(a, b) return (a.name or "") < (b.name or "") end)
            table.insert(out, "<div class='sidebar-section'>")
            table.insert(out, string.format("<div class='sidebar-section-title'>%s</div>", sec.title))
            for _, item in ipairs(matching) do
                table.insert(out, string.format(
                    "<a class='item-link' href='#%s' title='%s'>%s</a>",
                    item.anchor_id or item.name,
                    escape_html(item.name),
                    escape_html(item.name)
                ))
            end
            table.insert(out, "</div>")
        end
    end

    return table.concat(out, "\n")
end

--- Renders declaration box and doc block for a single AST item
function Generator:render_item(item, current_file)
    local out = {}
    local kind_label = "Item"
    local badge_label = ""

    if item.kind == ast.KIND.FUNCTION then
        kind_label = "Function"
        badge_label = "fn"
    elseif item.kind == ast.KIND.STRUCT then
        kind_label = "Struct"
        badge_label = "struct"
    elseif item.kind == ast.KIND.UNION then
        kind_label = "Union"
        badge_label = "union"
    elseif item.kind == ast.KIND.ENUM then
        kind_label = "Enum"
        badge_label = "enum"
    elseif item.kind == ast.KIND.TYPEDEF then
        kind_label = "Type Alias"
        badge_label = "type"
    end

    local anchor = item.anchor_id or item.name
    table.insert(out, string.format(
        "<h2 id='%s'><span>%s <span class='badge'>%s</span></span><a class='anchor-link' href='#%s' title='Link to this item'>#</a></h2>",
        anchor,
        escape_html(item.name),
        badge_label,
        anchor
    ))

    -- Code declaration block
    table.insert(out, "<div class='item-decl'>")

    if item.kind == ast.KIND.FUNCTION then
        local ret = self:linkify_type(item.return_type, current_file)
        local fn_name = self.syntax:function_name(item.name)

        if #item.parameters == 0 then
            table.insert(out, string.format("%s %s();", ret, fn_name))
        else
            table.insert(out, string.format("%s %s(", ret, fn_name))
            for idx, p in ipairs(item.parameters) do
                local p_type = self:linkify_type(p.type, current_file)
                local p_name = escape_html(p.name)
                local comma = (idx < #item.parameters) and "," or ""
                table.insert(out, string.format("\n    %s %s%s", p_type, p_name, comma))
            end
            table.insert(out, "\n);")
        end

    elseif item.kind == ast.KIND.STRUCT or item.kind == ast.KIND.UNION then
        local kw = (item.kind == ast.KIND.STRUCT) and self.syntax:keyword("struct") or self.syntax:keyword("union")
        local type_name = self.syntax:type(item.name, nil)
        table.insert(out, string.format("%s %s {", kw, type_name))
        for _, f in ipairs(item.fields or {}) do
            local f_type = self:linkify_type(f.type, current_file)
            local f_name = escape_html(f.name)
            table.insert(out, string.format("\n    %s %s;", f_type, f_name))
        end
        table.insert(out, "\n};")

    elseif item.kind == ast.KIND.ENUM then
        local kw = self.syntax:keyword("enum")
        local type_name = self.syntax:type(item.name, nil)
        table.insert(out, string.format("%s %s {", kw, type_name))
        for _, v in ipairs(item.variants or {}) do
            local v_name = escape_html(v.name)
            local v_val = self.syntax:literal(v.value)
            table.insert(out, string.format("\n    %s = %s,", v_name, v_val))
        end
        table.insert(out, "\n};")

    elseif item.kind == ast.KIND.TYPEDEF then
        local kw = self.syntax:keyword("typedef")
        if item.return_type and #item.parameters > 0 then
            local ret = self:linkify_type(item.return_type, current_file)
            local td_name = escape_html(item.name)
            table.insert(out, string.format("%s %s (*%s)(", kw, ret, td_name))
            for idx, p in ipairs(item.parameters) do
                local p_type = self:linkify_type(p.type, current_file)
                local p_name = escape_html(p.name)
                local comma = (idx < #item.parameters) and ", " or ""
                table.insert(out, string.format("%s %s%s", p_type, p_name, comma))
            end
            table.insert(out, ");")
        else
            local under = self:linkify_type(item.underlying_type, current_file)
            local td_name = escape_html(item.name)
            table.insert(out, string.format("%s %s %s;", kw, under, td_name))
        end
    end

    table.insert(out, "</div>")

    -- Documentation block
    if item.documentation then
        table.insert(out, self:render_doc_block(item.documentation, current_file))
    end

    -- Fields or Variants detailed documentation
    if (item.kind == ast.KIND.STRUCT or item.kind == ast.KIND.UNION) and item.fields then
        local has_field_docs = false
        for _, f in ipairs(item.fields) do
            if f.documentation then has_field_docs = true break end
        end

        if has_field_docs then
            table.insert(out, "<h3>Fields</h3>")
            for _, f in ipairs(item.fields) do
                if f.documentation then
                    table.insert(out, string.format("<div id='%s' class='field-item'>", f.name))
                    table.insert(out, string.format("<code class='field-name'>%s</code>", escape_html(f.name)))
                    table.insert(out, "<div class='field-doc'>")
                    table.insert(out, self:render_doc_block(f.documentation, current_file))
                    table.insert(out, "</div></div>")
                end
            end
        end
    elseif item.kind == ast.KIND.ENUM and item.variants then
        local has_var_docs = false
        for _, v in ipairs(item.variants) do
            if v.documentation then has_var_docs = true break end
        end

        if has_var_docs then
            table.insert(out, "<h3>Variants</h3>")
            for v_idx, v in ipairs(item.variants) do
                if v.documentation then
                    table.insert(out, string.format("<div id='%s' class='field-item'>", v.name))
                    table.insert(out, string.format("<code class='field-name'>%s = %s</code>", escape_html(v.name), escape_html(v.value)))
                    table.insert(out, "<div class='field-doc'>")
                    table.insert(out, self:render_doc_block(v.documentation, current_file))
                    table.insert(out, "</div></div>")
                end
            end
        end
    end

    return table.concat(out, "\n")
end

--- Generates HTML page for a single header
function Generator:generate_module_html(module_node)
    local main_out = {}

    table.insert(main_out, string.format(
        "<h1>Header <span class='fn'>%s</span></h1>",
        escape_html(module_node.name)
    ))

    if module_node.documentation then
        table.insert(main_out, self:render_doc_block(module_node.documentation, module_node.name))
    end

    for idx, item in ipairs(module_node.items) do
        table.insert(main_out, self:render_item(item, module_node.name))
    end

    local sidebar_html = self:build_sidebar(module_node)

    local res = page_structure.render({
        title = module_node.name .. " - Ballistic Documentation",
        filename = module_node.name,
        sidebar_content = sidebar_html,
        main_content = table.concat(main_out, "\n"),
        color_picker = self.colors,
    })
    return res
end

--- Generates index.html listing all parsed headers and symbol directory
function Generator:generate_index_html(modules)
    local sidebar_out = {
        "<div class='sidebar-title'>Ballistic Docs</div>",
        "<div class='sidebar-section'><div class='sidebar-section-title'>Headers</div>"
    }

    local sorted_mods = {}
    for _, mod in ipairs(modules) do
        table.insert(sorted_mods, mod)
    end
    table.sort(sorted_mods, function(a, b) return a.name < b.name end)

    for _, mod in ipairs(sorted_mods) do
        table.insert(sidebar_out, string.format(
            "<a class='item-link' href='%s.html'>%s</a>",
            mod.name, escape_html(mod.name)
        ))
    end
    table.insert(sidebar_out, "</div>")

    local main_out = {
        "<h1>Ballistic API Documentation</h1>",
        "<div class='docblock'><p>Generated C documentation with Rustdoc/docs.rs inspired layout and symbol cross-referencing.</p></div>",
        "<h2>Headers</h2>",
        "<ul>"
    }

    for _, mod in ipairs(sorted_mods) do
        local summary = ""
        if mod.documentation and mod.documentation.summary then
            summary = " &mdash; " .. escape_html(mod.documentation.summary:sub(1, 120))
            if #mod.documentation.summary > 120 then summary = summary .. "..." end
        end
        table.insert(main_out, string.format(
            "<li><a href='%s.html'><strong>%s</strong></a>%s</li>",
            mod.name, escape_html(mod.name), summary
        ))
    end
    table.insert(main_out, "</ul>")

    -- Symbol index
    if self.registry and self.registry.symbols then
        table.insert(main_out, "<h2>Global Symbols</h2>")
        table.insert(main_out, "<div class='symbol-grid'>")

        local sym_list = {}
        for name, item in pairs(self.registry.symbols) do
            -- Filter out subfields for cleaner index
            if not name:find("%.") then
                table.insert(sym_list, item)
            end
        end
        table.sort(sym_list, function(a, b) return a.name < b.name end)

        for _, sym in ipairs(sym_list) do
            local link = string.format("%s.html#%s", sym.file, sym.anchor)
            table.insert(main_out, string.format(
                "<a class='symbol-card' href='%s'><div class='symbol-card-name'>%s</div><div class='symbol-card-file'>%s (%s)</div></a>",
                link,
                escape_html(sym.name),
                escape_html(sym.file),
                escape_html(sym.kind or "")
            ))
        end
        table.insert(main_out, "</div>")
    end

    return page_structure.render({
        title = "Ballistic API Documentation",
        filename = "index.html",
        sidebar_content = table.concat(sidebar_out, "\n"),
        main_content = table.concat(main_out, "\n"),
        color_picker = self.colors,
    })
end

--- Ensures a directory exists
local function ensure_dir(path)
    if not path or path == "" then return end
    -- Normalize slashes
    local norm = path:gsub("\\", "/")
    if jit and jit.os == "Windows" then
        local win_path = norm:gsub("/", "\\")
        os.execute('if not exist "' .. win_path .. '" mkdir "' .. win_path .. '" >nul 2>&1')
    else
        os.execute('mkdir -p "' .. norm .. '" >/dev/null 2>&1')
    end
end

--- Generates all documentation files into out_dir
function Generator:generate_all(project, out_dir)
    out_dir = out_dir or "docs"
    ensure_dir(out_dir)

    self.registry = project.registry

    log.info("Generating documentation into '%s'...", out_dir)

    -- Generate module files
    for _, mod in ipairs(project.modules) do
        local html = self:generate_module_html(mod)
        local out_path = string.format("%s/%s.html", out_dir, mod.name)
        local f = io.open(out_path, "w")
        if f then
            f:write(html)
            f:close()
            log.debug("Wrote %s", out_path)
        else
            log.error("Failed to write %s", out_path)
        end
    end

    local index_html = self:generate_index_html(project.modules)
    local index_path = string.format("%s/index.html", out_dir)
    local idx_f = io.open(index_path, "w")
    if idx_f then
        idx_f:write(index_html)
        idx_f:close()
        log.debug("Wrote %s", index_path)
    else
        log.error("Failed to write %s", index_path)
    end
end

--- Creates a new Generator instance with Dependency Injection
function M.create(options)
    options = options or {}
    local self = setmetatable({}, Generator)
    self.colors = options.color_picker or color_picker.create(options.theme or "dark")
    self.syntax = options.syntax_picker or syntax_picker.create()
    self.registry = options.registry
    return self
end

return M
