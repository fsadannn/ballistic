local ffi = require("ffi")
local log = require("log")
local ast = require("ast")
local documentation = require("documentation")
local clang = require("clang")

local M = {}

--- Extracts file-level documentation from a header.
--- Supports both //! comments and leading /** @file ... */ or /*! ... */ comment blocks.
local function parse_file_level_docs(header_path)
    local file = io.open(header_path, "r")
    if not file then
        log.error("parser: cannot open '%s' for file-level docs", header_path)
        return nil
    end

    local lines = {}
    local is_bang_mode = false
    local in_c_comment = false
    local c_comment_lines = {}

    for line in file:lines() do
        local stripped = line:match("^%s*(.-)%s*$") or ""

        if stripped:sub(1, 3) == "//!" then
            is_bang_mode = true
            local content = stripped:sub(4)
            if content:sub(1, 1) == " " then
                content = content:sub(2)
            end
            table.insert(lines, content)
        elseif not is_bang_mode then
            if not in_c_comment then
                if stripped:sub(1, 3) == "/**" or stripped:sub(1, 3) == "/*!" or stripped:sub(1, 2) == "/*" then
                    in_c_comment = true
                    table.insert(c_comment_lines, stripped)
                    if stripped:find("%*/") then
                        in_c_comment = false
                        break
                    end
                elseif stripped ~= "" and not stripped:match("^#") then
                    -- Hit non-comment code before finding a doc block
                    break
                end
            else
                table.insert(c_comment_lines, stripped)
                if stripped:find("%*/") then
                    in_c_comment = false
                    break
                end
            end
        end
    end
    file:close()

    if #lines > 0 then
        local raw = table.concat(lines, "\n")
        return documentation.parse(raw)
    elseif #c_comment_lines > 0 then
        local raw = table.concat(c_comment_lines, "\n")
        return documentation.parse(raw)
    end

    return nil
end

local function struct_visitor(cursor, parent, fields, clang_context, filepath)
    local kind = clang.cursor_kind(clang_context, cursor)
    if kind == clang.CURSOR_KIND.FIELD_DECL then
        local name = clang.cursor_spelling(clang_context, cursor)
        local raw_type = clang.type_spelling(clang_context, clang.cursor_type(clang_context, cursor))
        local raw_comment = clang.raw_comment(clang_context, cursor)
        local doc = documentation.parse(raw_comment)
        local loc = clang.cursor_location(clang_context, cursor, filepath)
        local f = ast.create_field(name, raw_type, doc, loc)
        table.insert(fields, f)
    end
    return clang.CHILD_VISIT.CONTINUE
end

local function enum_visitor(cursor, parent, variants, clang_context, filepath)
    local kind = clang.cursor_kind(clang_context, cursor)
    if kind == clang.CURSOR_KIND.ENUM_CONSTANT_DECL then
        local name = clang.cursor_spelling(clang_context, cursor)
        local val = tostring(clang_context.library.clang_getEnumConstantDeclValue(cursor))
        local raw_comment = clang.raw_comment(clang_context, cursor)
        local doc = documentation.parse(raw_comment)
        local loc = clang.cursor_location(clang_context, cursor, filepath)
        local v = ast.create_variant(name, val, doc, loc)
        table.insert(variants, v)
    end
    return clang.CHILD_VISIT.CONTINUE
end

local function typedef_param_visitor(cursor, parent, params, clang_context)
    local kind = clang.cursor_kind(clang_context, cursor)
    if kind == clang.CURSOR_KIND.PARM_DECL then
        local name = clang.cursor_spelling(clang_context, cursor)
        local raw_type = clang.type_spelling(clang_context, clang.cursor_type(clang_context, cursor))
        local p = ast.create_parameter(name, raw_type)
        table.insert(params, p)
    end
    return clang.CHILD_VISIT.CONTINUE
end

--- Creates and parses a libclang translation unit for the specified header.
--- Returns index, translation_unit, own_index on success, or nil, nil, false on failure.
local function create_translation_unit(clang_context, header_path, clang_args, shared_index)
    local file = io.open(header_path, "r")
    if not file then
        log.error("Aborting function: Failed to open header file %s.", header_path)
        return nil, nil, false
    end
    file:close()

    if not clang_context or not clang_context.library then
        log.error("Aborting function: libclang not initialized.")
        return nil, nil, false
    end

    local args = clang_args or {}
    local argc = #args
    local argv = nil

    if argc > 0 then
        argv = ffi.new("const char*[?]", argc)
        for i = 1, argc do
            argv[i - 1] = args[i]
        end
    end

    local clang_library = clang_context.library
    local own_index = false
    local index = shared_index
    if not index then
        index = clang_library.clang_createIndex(0, 0)
        own_index = true
    end

    local unsaved_files = nil
    local num_unsaved_files = 0
    local options = 0x40 -- CXTranslationUnit_SkipFunctionBodies

    local ok, translation_unit = pcall(
        clang_library.clang_parseTranslationUnit,
        index, header_path, argv, argc, unsaved_files, num_unsaved_files, options
    )

    if not ok then
        if own_index then clang_library.clang_disposeIndex(index) end
        log.error("Aborting function: failed to parse translation unit because %s.", tostring(translation_unit))
        return nil, nil, false
    end

    if translation_unit == nil then
        if own_index then clang_library.clang_disposeIndex(index) end
        log.error("Aborting function: failed to create translation unit for %s.", header_path)
        return nil, nil, false
    end

    return index, translation_unit, own_index
end

local function already_seen(ctx, name)
    if not name or name == "" then return true end
    if ctx.seen_names[name] then return true end
    ctx.seen_names[name] = true
    return false
end

local function register_symbol(ctx, name, anchor, kind, extra)
    if not ctx.project_registry or not name or name == "" then return end
    ctx.project_registry:register(name, ctx.module_name, anchor, kind, extra)
end

local function register_record_fields(ctx, record_name, fields)
    for _, f in ipairs(fields) do
        register_symbol(ctx, record_name .. "." .. f.name, f.name, "field", { parent = record_name })
    end
end

local function register_enum_variants(ctx, enum_name, variants)
    for _, v in ipairs(variants) do
        register_symbol(ctx, v.name, v.name, "variant", { parent = enum_name })
    end
end

local function parse_function_decl(ctx, cursor)
    local name = clang.cursor_spelling(ctx.clang_context, cursor)
    if already_seen(ctx, name) then return end

    local loc = clang.cursor_location(ctx.clang_context, cursor, ctx.header_path)
    local clang_library = ctx.clang_context.library
    local raw_doc = clang.raw_comment(ctx.clang_context, cursor)
    local doc = documentation.parse(raw_doc)
    local ret_type = clang.type_spelling(
        ctx.clang_context,
        clang_library.clang_getCursorResultType(cursor)
    )
    local num_args = clang_library.clang_Cursor_getNumArguments(cursor)
    local parameters = {}
    for i = 0, num_args - 1 do
        local arg_cursor = clang_library.clang_Cursor_getArgument(cursor, i)
        local arg_name = clang.cursor_spelling(ctx.clang_context, arg_cursor)
        local arg_type = clang.type_spelling(
            ctx.clang_context,
            clang.cursor_type(ctx.clang_context, arg_cursor)
        )
        table.insert(parameters, ast.create_parameter(arg_name, arg_type))
    end

    local fn_node = ast.create_function(name, ret_type, parameters, doc, loc)
    fn_node.anchor_id = "fn." .. name
    table.insert(ctx.module_node.items, fn_node)
    register_symbol(ctx, name, fn_node.anchor_id, "function")
end

local function parse_record_decl(ctx, cursor, is_union)
    if not clang.is_definition(ctx.clang_context, cursor) or clang.is_skippable(ctx.clang_context, cursor) then
        return
    end
    local name = clang.cursor_spelling(ctx.clang_context, cursor)
    if already_seen(ctx, name) then return end

    local loc = clang.cursor_location(ctx.clang_context, cursor, ctx.header_path)
    local raw_doc = clang.raw_comment(ctx.clang_context, cursor)
    local doc = documentation.parse(raw_doc)
    local fields = {}
    clang.visit_children(ctx.clang_context, cursor, function(c, p)
        return struct_visitor(c, p, fields, ctx.clang_context, ctx.header_path)
    end)

    local node, kind
    if is_union then
        node = ast.create_union(name, fields, doc, loc)
        node.anchor_id = "union." .. name
        kind = "union"
    else
        node = ast.create_struct(name, fields, doc, loc)
        node.anchor_id = "struct." .. name
        kind = "struct"
    end

    table.insert(ctx.module_node.items, node)
    register_symbol(ctx, name, node.anchor_id, kind)
    register_record_fields(ctx, name, fields)
end

local function parse_enum_decl(ctx, cursor)
    if not clang.is_definition(ctx.clang_context, cursor) or clang.is_skippable(ctx.clang_context, cursor) then
        return
    end
    local name = clang.cursor_spelling(ctx.clang_context, cursor)
    if already_seen(ctx, name) then return end

    local loc = clang.cursor_location(ctx.clang_context, cursor, ctx.header_path)
    local raw_doc = clang.raw_comment(ctx.clang_context, cursor)
    local doc = documentation.parse(raw_doc)
    local variants = {}
    clang.visit_children(ctx.clang_context, cursor, function(c, p)
        return enum_visitor(c, p, variants, ctx.clang_context, ctx.header_path)
    end)

    local enum_node = ast.create_enum(name, variants, doc, loc)
    enum_node.anchor_id = "enum." .. name
    table.insert(ctx.module_node.items, enum_node)
    register_symbol(ctx, name, enum_node.anchor_id, "enum")
    register_enum_variants(ctx, name, variants)
end

local function parse_typedef_record(ctx, cursor, name, canonical)
    local loc = clang.cursor_location(ctx.clang_context, cursor, ctx.header_path)
    local clang_library = ctx.clang_context.library
    local raw_doc = clang.raw_comment(ctx.clang_context, cursor)
    local sc = clang_library.clang_getTypeDeclaration(canonical)
    if not raw_doc or raw_doc == "" then
        raw_doc = clang.raw_comment(ctx.clang_context, sc)
    end
    local doc = documentation.parse(raw_doc)
    local fields = {}
    clang.visit_children(ctx.clang_context, sc, function(c, p)
        return struct_visitor(c, p, fields, ctx.clang_context, ctx.header_path)
    end)

    local struct_node = ast.create_struct(name, fields, doc, loc)
    struct_node.anchor_id = "struct." .. name
    table.insert(ctx.module_node.items, struct_node)
    register_symbol(ctx, name, struct_node.anchor_id, "struct")
    register_record_fields(ctx, name, fields)
end

local function parse_typedef_enum(ctx, cursor, name, canonical)
    local loc = clang.cursor_location(ctx.clang_context, cursor, ctx.header_path)
    local clang_library = ctx.clang_context.library
    local raw_doc = clang.raw_comment(ctx.clang_context, cursor)
    local sc = clang_library.clang_getTypeDeclaration(canonical)
    if not raw_doc or raw_doc == "" then
        raw_doc = clang.raw_comment(ctx.clang_context, sc)
    end
    local doc = documentation.parse(raw_doc)
    local variants = {}
    clang.visit_children(ctx.clang_context, sc, function(c, p)
        return enum_visitor(c, p, variants, ctx.clang_context, ctx.header_path)
    end)

    local enum_node = ast.create_enum(name, variants, doc, loc)
    enum_node.anchor_id = "enum." .. name
    table.insert(ctx.module_node.items, enum_node)
    register_symbol(ctx, name, enum_node.anchor_id, "enum")
    register_enum_variants(ctx, name, variants)
end

local function parse_typedef_alias(ctx, cursor, name, underlying)
    local loc = clang.cursor_location(ctx.clang_context, cursor, ctx.header_path)
    local clang_library = ctx.clang_context.library
    local raw_doc = clang.raw_comment(ctx.clang_context, cursor)
    local doc = documentation.parse(raw_doc)
    local underlying_type = clang.type_spelling(ctx.clang_context, underlying)
    local ret_type = nil
    local params = {}

    if underlying.kind == clang.TYPE_KIND.POINTER then
        local pointee = clang_library.clang_getPointeeType(underlying)
        if pointee.kind == clang.TYPE_KIND.FUNCTION_PROTO then
            ret_type = clang.type_spelling(
                ctx.clang_context,
                clang_library.clang_getResultType(pointee)
            )
            clang.visit_children(ctx.clang_context, cursor, function(c, p)
                return typedef_param_visitor(c, p, params, ctx.clang_context)
            end)
        end
    end

    local td_node = ast.create_typedef(name, underlying_type, ret_type, params, doc, loc)
    td_node.anchor_id = "type." .. name
    table.insert(ctx.module_node.items, td_node)
    register_symbol(ctx, name, td_node.anchor_id, "typedef")
end

local function parse_typedef_decl(ctx, cursor)
    local name = clang.cursor_spelling(ctx.clang_context, cursor)
    if already_seen(ctx, name) then return end

    local clang_library = ctx.clang_context.library
    local underlying = clang_library.clang_getTypedefDeclUnderlyingType(cursor)
    local canonical = clang_library.clang_getCanonicalType(underlying)

    if canonical.kind == clang.TYPE_KIND.RECORD then
        parse_typedef_record(ctx, cursor, name, canonical)
    elseif canonical.kind == clang.TYPE_KIND.ENUM then
        parse_typedef_enum(ctx, cursor, name, canonical)
    else
        parse_typedef_alias(ctx, cursor, name, underlying)
    end
end

--- Dispatch table for parse functions for different types
local DECL_HANDLERS = {
    [clang.CURSOR_KIND.FUNCTION_DECL] = parse_function_decl,
    [clang.CURSOR_KIND.STRUCT_DECL] = function(ctx, cursor, loc) parse_record_decl(ctx, cursor, loc, false) end,
    [clang.CURSOR_KIND.UNION_DECL] = function(ctx, cursor, loc) parse_record_decl(ctx, cursor, loc, true) end,
    [clang.CURSOR_KIND.ENUM_DECL] = parse_enum_decl,
    [clang.CURSOR_KIND.TYPEDEF_DECL] = parse_typedef_decl,
}

--- Visitor function tal will be called from `clang.visit_children` to traverse the parsed file
local function visit_node(ctx, cursor, parent)
    -- Skip nodes that are not from the main file (e.g. included headers, system headers)
    if not clang.is_from_main_file(ctx.clang_context, cursor) then
        return clang.CHILD_VISIT.CONTINUE
    end

    local kind = clang.cursor_kind(ctx.clang_context, cursor)
    local handler = DECL_HANDLERS[kind]
    if handler then
        local loc = clang.cursor_location(ctx.clang_context, cursor, ctx.header_path)
        handler(ctx, cursor, loc)
        return clang.CHILD_VISIT.CONTINUE
    end

    -- Recurse into unexposed decls (like extern "C")
    return clang.CHILD_VISIT.RECURSE
end

--- Parses a single header file and extracts its AST module node.
--- Optionally populates project_registry with found symbols for link resolution.
function M.parse_header(clang_context, header_path, clang_args, project_registry, shared_index)
    log.info("Parsing header %s.", header_path)

    local index, translation_unit, own_index = create_translation_unit(clang_context, header_path, clang_args, shared_index)
    if not translation_unit then
        return nil
    end

    log.debug("Translation unit created successfully for %s.", header_path)

    local file_level_documentation = parse_file_level_docs(header_path)
    local module_name = header_path:match("([^/\\]+)$") or header_path
    local module_node = ast.create_module(module_name, header_path, file_level_documentation)

    local ctx = {
        clang_context = clang_context,
        header_path = header_path,
        module_name = module_name,
        module_node = module_node,
        project_registry = project_registry,
        seen_names = {},
    }

    local clang_library = clang_context.library
    local root_cursor = clang_library.clang_getTranslationUnitCursor(translation_unit)

    clang.visit_children(clang_context, root_cursor, function(cursor, parent)
        return visit_node(ctx, cursor, parent)
    end)

    clang_library.clang_disposeTranslationUnit(translation_unit)
    if own_index then
        clang_library.clang_disposeIndex(index)
    end

    log.info("Finished parsing %s (%d items).", header_path, #module_node.items)
    return module_node
end

return M