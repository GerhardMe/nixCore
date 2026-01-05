local map = vim.keymap.set
local opts = {noremap = true, silent = true}

map("n", "<Space>", "", opts) -- Leader key
vim.g.mapleader = " "

-- Telescope
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", opts)
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", opts)
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", opts)
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", opts)

-- File explorer toggle (kept)
map("n", "<leader>e", "<cmd>NvimTreeToggle<CR>", opts)

-- Window navigation
map("n", "<Tab>", "<cmd>wincmd w<CR>", opts) -- next window

-- Safer saves: <C-s> in normal/insert/visual
vim.keymap.set(
    {"n", "i", "v"},
    "<C-s>",
    function()
        vim.cmd("silent! write")
    end,
    {silent = true, desc = "Save"}
)

-- Format current buffer
vim.keymap.set(
    "n",
    "<leader>f",
    function()
        local ok, conform = pcall(require, "conform")
        if ok then
            conform.format({async = false, lsp_fallback = true})
        else
            vim.lsp.buf.format({async = false})
        end
    end,
    {silent = true, desc = "Format"}
)
