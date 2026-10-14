-- Neovim 0.12+: native package management, with every plugin pinned.
vim.g.mapleader = ' '
vim.g.maplocalleader = ','

local o = vim.opt
o.number = true
o.relativenumber = true
o.termguicolors = true
o.signcolumn = 'yes'
o.cursorline = true
o.ignorecase = true
o.smartcase = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.splitbelow = true
o.splitright = true
o.scrolloff = 6
o.sidescrolloff = 6
o.updatetime = 250
o.timeoutlen = 400
o.undofile = true
o.swapfile = false
o.completeopt = { 'menuone', 'noselect', 'popup' }
o.clipboard = 'unnamedplus'
o.list = true
o.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

if not vim.pack then
  error('This configuration needs Neovim 0.12+. Run the dotfiles dependency installer.')
end
vim.pack.add({
  { src = 'https://github.com/folke/tokyonight.nvim', version = 'cdc07ac78467a233fd62c493de29a17e0cf2b2b6' },
  { src = 'https://github.com/nvim-mini/mini.nvim', version = '1345d191bb3da9c7b0e977f4387c5761f9bff68d' },
}, { confirm = false })
require('tokyonight').setup({ style = 'storm' })
vim.cmd.colorscheme('tokyonight-storm')
for _, module in ipairs({ 'icons', 'statusline', 'pick', 'extra', 'files', 'surround', 'pairs', 'diff', 'completion' }) do
  require('mini.' .. module).setup()
end

local map = vim.keymap.set
map('n', '<leader>ff', MiniPick.builtin.files, { desc = 'Find files' })
map('n', '<leader>fg', MiniPick.builtin.grep_live, { desc = 'Search project text' })
map('n', '<leader>fb', MiniPick.builtin.buffers, { desc = 'Find buffers' })
map('n', '<leader>fh', MiniPick.builtin.help, { desc = 'Search help' })
map('n', '<leader>gs', MiniExtra.pickers.git_hunks, { desc = 'Pick Git hunks' })
map('n', '<leader>e', function() MiniFiles.open(vim.api.nvim_buf_get_name(0), true) end, { desc = 'File explorer' })
map('n', '<Esc>', '<Cmd>nohlsearch<CR>')
for key, direction in pairs({ h = 'h', j = 'j', k = 'k', l = 'l' }) do
  map('n', '<C-' .. key .. '>', '<C-w>' .. direction, { desc = 'Move to split' })
end
map('n', '<leader>w', '<Cmd>write<CR>', { desc = 'Save file' })
map('n', '<leader>q', '<Cmd>copen<CR>', { desc = 'Open quickfix' })

vim.api.nvim_create_autocmd('TextYankPost', {
  group = vim.api.nvim_create_augroup('DotfilesYank', { clear = true }),
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})

-- Use project-installed language servers when available; never auto-install
-- another runtime or language server just because a file was opened.
vim.lsp.config('rust_analyzer', {
  cmd = { 'rust-analyzer' }, filetypes = { 'rust' },
  root_markers = { 'Cargo.toml', 'rust-project.json', '.git' },
})
if vim.fn.executable('rust-analyzer') == 1 then
  vim.lsp.enable('rust_analyzer')
end
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('DotfilesLsp', { clear = true }),
  callback = function(event)
    local opts = { buffer = event.buf }
    map('n', 'gd', vim.lsp.buf.definition, opts)
    map('n', 'gr', vim.lsp.buf.references, opts)
    map('n', 'K', vim.lsp.buf.hover, opts)
    map('n', '<leader>rn', vim.lsp.buf.rename, opts)
    map('n', '<leader>ca', vim.lsp.buf.code_action, opts)
    map('n', '<leader>cf', function() vim.lsp.buf.format({ async = true }) end, opts)
  end,
})

local local_config = vim.fn.stdpath('config') .. '/local.lua'
if vim.fn.filereadable(local_config) == 1 then dofile(local_config) end
