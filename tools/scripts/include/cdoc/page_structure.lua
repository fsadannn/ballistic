local log = require("log")

local M = {}

--- Renders a complete HTML page with docs.rs style, including responsive sidebar and modern typography.
--- `params` table expects:
---   title: string (HTML page title)
---   filename: string (e.g. "bal_assembler.h")
---   sidebar_content: string (HTML for sidebar navigation)
---   main_content: string (HTML for main content)
---   color_picker: ColorPicker instance (from color_picker.lua)
function M.render(params)
    local title = params.title or "Documentation"
    local color_picker = params.color_picker
    local css_variables = color_picker and color_picker:get_css_variables() or ""
    local sidebar = params.sidebar_content or ""
    local main = params.main_content or ""

    local parts = {
        '<!DOCTYPE html>\n<html lang="en">\n<head>\n',
        '    <meta charset="utf-8">\n',
        '    <meta name="viewport" content="width=device-width, initial-scale=1.0">\n',
        '    <title>', title, '</title>\n',
        '    <link rel="preconnect" href="https://fonts.googleapis.com">\n',
        '    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n',
        '    <link href="https://fonts.googleapis.com/css2?family=Fira+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&family=Source+Code+Pro:wght@400;500;600;700&family=Source+Serif+4:ital,opsz,wght@0,8..60,400;0,8..60,600;0,8..60,700;1,8..60,400&display=swap" rel="stylesheet">\n',
        '    <style>\n',
        css_variables, '\n\n',
[[
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Source Serif 4', Georgia, serif;
            font-size: 16px;
            background: var(--bg);
            color: var(--text);
            display: flex;
            min-height: 100vh;
            line-height: 1.6;
        }
        .sidebar {
            width: 270px;
            background: var(--sidebar-bg);
            border-right: 1px solid var(--border);
            overflow-y: auto;
            padding: 24px 18px;
            flex-shrink: 0;
            height: 100vh;
            position: sticky;
            top: 0;
            font-family: 'Fira Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        .sidebar-title {
            font-size: 1.15em;
            font-weight: 700;
            color: var(--header-text);
            margin-bottom: 16px;
            padding-bottom: 8px;
            border-bottom: 1px solid var(--border);
            word-break: break-all;
        }
        .sidebar-back {
            display: inline-block;
            font-size: 0.9em;
            color: var(--link);
            text-decoration: none;
            margin-bottom: 16px;
            font-weight: 500;
        }
        .sidebar-back:hover { text-decoration: underline; }
        .sidebar-section {
            margin-top: 18px;
        }
        .sidebar-section-title {
            font-size: 0.78em;
            text-transform: uppercase;
            letter-spacing: 0.08em;
            color: var(--badge-text);
            font-weight: 700;
            margin-bottom: 8px;
        }
        .sidebar a.item-link {
            display: block;
            color: var(--sidebar-text);
            text-decoration: none;
            font-size: 0.88em;
            padding: 3px 6px;
            border-radius: 4px;
            margin: 2px 0;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .sidebar a.item-link:hover {
            color: var(--link);
            background: var(--sidebar-hover);
        }
        .main {
            flex: 1;
            padding: 40px 50px;
            max-width: 1020px;
            margin: 0 auto;
            overflow-x: auto;
        }
        h1, h2, h3, h4 {
            font-family: 'Fira Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            color: var(--header-text);
        }
        h1 {
            font-size: 2.1em;
            font-weight: 700;
            margin-bottom: 24px;
            padding-bottom: 12px;
            border-bottom: 1px solid var(--border);
        }
        h2 {
            font-size: 1.45em;
            font-weight: 600;
            margin-top: 48px;
            margin-bottom: 16px;
            padding-bottom: 6px;
            border-bottom: 1px solid var(--border);
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        h2 .anchor-link {
            color: var(--badge-text);
            text-decoration: none;
            font-size: 0.85em;
            opacity: 0.4;
            transition: opacity 0.2s;
        }
        h2:hover .anchor-link { opacity: 1; }
        h3 {
            font-size: 1.18em;
            font-weight: 600;
            margin-top: 24px;
            margin-bottom: 12px;
        }
        a {
            color: var(--link);
            text-decoration: none;
        }
        a:hover { text-decoration: underline; }
        a.type {
            color: var(--type-color);
            text-decoration: none;
            border-bottom: 1px dotted rgba(121, 192, 255, 0.4);
        }
        a.type:hover {
            border-bottom: 1px solid var(--type-color);
        }
        .kw { color: var(--kw-color); font-weight: 600; }
        .type { color: var(--type-color); }
        .fn { color: var(--fn-color); font-weight: 600; }
        .lit { color: var(--lit-color); }
        .comment { color: var(--comment-color); font-style: italic; }
        .attr { color: var(--attr-color); }

        .item-decl {
            font-family: 'Source Code Pro', Consolas, Monaco, monospace;
            font-size: 0.9em;
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 14px 18px;
            margin-bottom: 16px;
            line-height: 1.6;
            overflow-x: auto;
            white-space: pre-wrap;
            word-break: break-all;
        }
        .docblock {
            margin-bottom: 32px;
            font-size: 1em;
            line-height: 1.7;
        }
        .docblock p {
            margin-bottom: 1em;
        }
        .docblock pre {
            background: var(--code-bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 14px 18px;
            margin: 16px 0;
            overflow-x: auto;
            font-family: 'Source Code Pro', monospace;
            font-size: 0.88em;
            line-height: 1.5;
        }
        .docblock code {
            font-family: 'Source Code Pro', monospace;
            background: var(--code-bg);
            padding: 0.15em 0.4em;
            border-radius: 4px;
            font-size: 0.9em;
            border: 1px solid var(--border);
        }
        .docblock ul, .docblock ol {
            margin-left: 24px;
            margin-bottom: 1em;
        }
        .docblock li {
            margin-bottom: 0.4em;
        }

        .callout {
            margin: 20px 0;
            padding: 14px 18px;
            border-left: 4px solid var(--callout-border);
            background: var(--callout-bg);
            border-radius: 0 6px 6px 0;
        }
        .callout.safety {
            border-left-color: var(--callout-safety-border);
            background: var(--callout-safety-bg);
        }
        .callout.errors {
            border-left-color: var(--callout-error-border);
            background: var(--callout-error-bg);
        }
        .callout-title {
            font-family: 'Fira Sans', sans-serif;
            font-weight: 700;
            font-size: 0.92em;
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        .field-item {
            margin: 14px 0 16px 12px;
            padding-left: 14px;
            border-left: 2px solid var(--border);
        }
        .field-name {
            font-family: 'Source Code Pro', monospace;
            font-weight: 600;
            color: var(--header-text);
            background: var(--code-bg);
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 0.92em;
            border: 1px solid var(--border);
            display: inline-block;
        }
        .field-doc {
            margin-top: 6px;
            color: var(--text);
            font-size: 0.95em;
        }
        .badge {
            display: inline-block;
            padding: 2px 8px;
            font-size: 0.72em;
            border-radius: 12px;
            background: var(--badge-bg);
            color: var(--badge-text);
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            vertical-align: middle;
            margin-left: 8px;
            font-family: 'Fira Sans', sans-serif;
        }
        .symbol-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
            gap: 12px;
            margin-top: 16px;
        }
        .symbol-card {
            background: var(--sidebar-bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 10px 14px;
            text-decoration: none;
            display: block;
            transition: border-color 0.2s, background-color 0.2s;
        }
        .symbol-card:hover {
            border-color: var(--link);
            background: var(--sidebar-hover);
            text-decoration: none;
        }
        .symbol-card-name {
            font-family: 'Source Code Pro', monospace;
            font-size: 0.9em;
            font-weight: 600;
            color: var(--header-text);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .symbol-card-file {
            font-size: 0.8em;
            color: var(--badge-text);
            margin-top: 4px;
        }
    </style>
</head>
<body>
    <nav class="sidebar">
]],
        sidebar,
[[
    </nav>
    <main class="main">
]],
        main,
[[
    </main>
</body>
</html>
]]
    }

    return table.concat(parts)
end

return M
