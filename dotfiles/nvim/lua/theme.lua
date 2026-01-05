-- lua/theme.lua
local M = {}

-- ===== Palette =====
local p = {
    bg = "#0b0d10", -- background (used if transparency is off)
    fg = "#ffffff", -- default foreground, "Normal" text
    dimfg = "#cccccc", -- dimmed text (inactive statusline, unfocused windows, etc.)
    gutter = "#8daaad", -- line numbers, signs, separators
    neon = "#8700ff", -- primary accent (purple) → functions, cursor line, highlights
    yellow = "#ffee00", -- constants, types, operators
    cyan = "#00e5ff", -- strings, success states, Git additions
    orange = "#ff6600", -- keywords, TODOs, search highlights
    green = "#3cff00", -- numbers, booleans, Git warnings
    red = "#ff0000", -- errors, Git deletions, critical highlights
    blue = "#003cff", -- secondary accent → statements, keywords, special punctuation
    magenta = "#ff0095" -- identifiers, fields, Git changes, info highlights
}

local tint_cmnt = "#939fe9" -- comments
local tint_gutter = "#baafbb" -- line numbers & gutter

local transparent = true
local function BG(c)
    return transparent and "NONE" or c
end
local function hi(group, specs)
    vim.api.nvim_set_hl(0, group, specs)
end

function M.setup()
    vim.g.colors_name = "neon"

    -- ===== Core UI =====
    hi("Normal", {fg = p.fg, bg = BG(p.bg)})
    hi("NormalFloat", {fg = p.fg, bg = BG(p.bg)})
    hi("FloatBorder", {fg = p.neon, bg = BG(p.bg)})
    hi("WinSeparator", {fg = tint_gutter, bg = BG(p.bg)})
    hi("SignColumn", {fg = tint_gutter, bg = BG(p.bg)})
    hi("LineNr", {fg = tint_gutter, bg = BG(p.bg)})
    hi("LineNrAbove", {fg = tint_gutter, bg = BG(p.bg)})
    hi("LineNrBelow", {fg = tint_gutter, bg = BG(p.bg)})

    -- Top title (per-window)
    hi("WinBar", {fg = p.cyan, bg = BG(p.bg), bold = true})
    hi("WinBarNC", {fg = p.dimfg, bg = BG(p.bg)})

    -- current line: make it visible even on transparent bg
    hi("CursorLine", {bg = "#1a0933"}) -- neon-purplish strip; change to "NONE", underline=true if you prefer
    hi("CursorLineNr", {fg = p.neon, bold = true})

    hi("Visual", {bg = "#10253a"}) -- cyan-tinted select
    hi("Search", {fg = "#000000", bg = p.yellow, bold = true})
    hi("IncSearch", {fg = "#000000", bg = p.orange, bold = true})
    hi("MatchParen", {fg = p.yellow, underline = true})

    -- Statusline / Tabs / Menus (neon forward)
    hi("StatusLine", {fg = p.fg, bg = "#171a22"})
    hi("StatusLineNC", {fg = p.dimfg, bg = "#111319"})
    hi("TabLine", {fg = p.dimfg, bg = "#111319"})
    hi("TabLineSel", {fg = p.neon, bg = "#1a1d27", bold = true})
    hi("Pmenu", {fg = p.fg, bg = "#0f1220"})
    hi("PmenuSel", {fg = "#000000", bg = p.magenta, bold = true})
    hi("PmenuSbar", {bg = "#1a1d2b"})
    hi("PmenuThumb", {bg = p.neon})
    hi("VertSplit", {fg = "#2a2d38"})

    -- ===== Syntax (Vim) – max neon diversity, minimal gray =====
    hi("Comment", {fg = tint_cmnt, italic = true}) -- gray w/ purple tint
    hi("Constant", {fg = p.cyan})
    hi("String", {fg = p.green})
    hi("Character", {fg = p.green, bold = true})
    hi("Number", {fg = p.orange})
    hi("Boolean", {fg = p.yellow, bold = true})
    hi("Identifier", {fg = p.blue, bold = true})
    hi("Function", {fg = p.neon, bold = true})
    hi("Statement", {fg = p.magenta})
    hi("Operator", {fg = p.cyan}) -- more color than gray
    hi("Keyword", {fg = p.magenta, bold = true})
    hi("Type", {fg = p.cyan})
    hi("Special", {fg = p.yellow})
    hi("Delimiter", {fg = p.neon}) -- punctuation pops
    hi("PreProc", {fg = p.orange})
    hi("Include", {fg = p.orange, bold = true})
    hi("Define", {fg = p.yellow})
    hi("Macro", {fg = p.yellow, bold = true})
    hi("StorageClass", {fg = p.red, bold = true})
    hi("Structure", {fg = p.blue})
    hi("TypeDef", {fg = p.cyan})

    -- ===== Treesitter (modern Neovim) =====
    hi("@comment", {link = "Comment"})
    hi("@string", {link = "String"})
    hi("@character", {link = "Character"})
    hi("@number", {link = "Number"})
    hi("@float", {fg = p.orange})
    hi("@boolean", {link = "Boolean"})
    hi("@constant", {link = "Constant"})
    hi("@constant.builtin", {fg = p.orange, bold = true})
    hi("@constant.macro", {fg = p.yellow})
    hi("@variable", {fg = p.fg}) -- normal text white
    hi("@variable.builtin", {fg = p.yellow})
    hi("@variable.parameter", {fg = p.cyan})
    hi("@field", {fg = p.blue})
    hi("@property", {fg = p.green})
    hi("@function", {link = "Function"})
    hi("@function.builtin", {fg = p.neon, bold = true})
    hi("@function.call", {fg = p.neon})
    hi("@constructor", {fg = p.magenta})
    hi("@keyword", {link = "Keyword"})
    hi("@keyword.function", {fg = p.magenta, bold = true})
    hi("@keyword.operator", {fg = p.cyan, bold = true})
    hi("@keyword.return", {fg = p.red, bold = true})
    hi("@operator", {link = "Operator"})
    hi("@type", {link = "Type"})
    hi("@type.builtin", {fg = p.cyan, bold = true})
    hi("@namespace", {fg = p.blue})
    hi("@punctuation.delimiter", {fg = p.neon})
    hi("@punctuation.bracket", {fg = p.magenta})
    hi("@punctuation.special", {fg = p.yellow})

    -- ===== Diagnostics (neon and readable) =====
    hi("DiagnosticError", {fg = p.red})
    hi("DiagnosticWarn", {fg = p.orange})
    hi("DiagnosticInfo", {fg = p.blue})
    hi("DiagnosticHint", {fg = p.green})
    hi("DiagnosticUnderlineError", {undercurl = true, sp = p.red})
    hi("DiagnosticUnderlineWarn", {undercurl = true, sp = p.orange})
    hi("DiagnosticUnderlineInfo", {undercurl = true, sp = p.blue})
    hi("DiagnosticUnderlineHint", {undercurl = true, sp = p.green})
    hi("DiagnosticVirtualTextError", {fg = p.red})
    hi("DiagnosticVirtualTextWarn", {fg = p.orange})
    hi("DiagnosticVirtualTextInfo", {fg = p.blue})
    hi("DiagnosticVirtualTextHint", {fg = p.green})

    -- ===== Git (gitsigns) =====
    hi("GitSignsAdd", {fg = p.green})
    hi("GitSignsChange", {fg = p.blue})
    hi("GitSignsDelete", {fg = p.red})
end

return M
