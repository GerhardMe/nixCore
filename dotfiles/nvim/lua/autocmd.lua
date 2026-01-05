-- Auto-save on insert leave, focus lost, etc.
--vim.api.nvim_create_autocmd(
--    {"InsertLeave", "TextChanged", "BufLeave", "FocusLost"},
--    {
--        callback = function()
--            if vim.bo.modifiable and vim.bo.buftype == "" then
--                vim.cmd("silent! update")
--            end
--        end
--    }
--)
-- Final safeguard: save all on exit
--vim.api.nvim_create_autocmd(
--    "VimLeavePre",
--    {
--        callback = function()
--            vim.cmd("silent! wall")
--        end
--    }
--)

-- Close certain buffers with <Esc>
vim.api.nvim_create_autocmd(
    "FileType",
    {
        pattern = {
            "lazy", -- lazy.nvim UI
            "help", -- :help
            "man", -- :Man
            "qf", -- quickfix
            "lspinfo", -- :LspInfo
            "checkhealth" -- :checkhealth
        },
        callback = function(event)
            vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", {buffer = event.buf, silent = true})
            vim.keymap.set("n", "q", "<cmd>close<CR>", {buffer = event.buf, silent = true}) -- still keep q
        end
    }
)

-- NvimTree-specific title = current project (cwd tail)
vim.api.nvim_create_autocmd(
    {"BufWinEnter", "WinEnter", "FileType"},
    {
        pattern = "NvimTree",
        callback = function()
            -- get the current working directory and show only its tail as title
            local root = vim.fn.fnamemodify(vim.loop.cwd(), ":t")
            vim.opt_local.winbar = ("%s/"):format(root)
        end
    }
)

-- if you ever leave the tree window, fall back to default
vim.api.nvim_create_autocmd(
    "BufWinLeave",
    {
        pattern = "NvimTree",
        callback = function()
            vim.opt_local.winbar = nil
        end
    }
)
