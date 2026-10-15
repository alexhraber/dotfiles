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
o.winborder = 'rounded'

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
require('mini.tabline').setup()
local scope = require('mini.indentscope')
scope.setup({ symbol = '│', draw = { animation = scope.gen_animation.none() } })
local starter = require('mini.starter')
starter.setup({
  header = 'a r x  /  w o r k b e n c h',
  footer = 'Space ff  files     Space fg  search     Space e  explorer',
  items = {
    { name = 'Find files', action = 'lua MiniPick.builtin.files()', section = 'Work' },
    { name = 'Search project', action = 'lua MiniPick.builtin.grep_live()', section = 'Work' },
    { name = 'New buffer', action = 'enew', section = 'Work' },
    starter.sections.recent_files(5, true),
    { name = 'Quit', action = 'qall', section = 'Session' },
  },
  content_hooks = { starter.gen_hook.adding_bullet('› '), starter.gen_hook.aligning('center', 'center') },
})

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
map('n', '[b', '<Cmd>bprevious<CR>', { desc = 'Previous buffer' })
map('n', ']b', '<Cmd>bnext<CR>', { desc = 'Next buffer' })
map('n', '<leader>ss', starter.open, { desc = 'Open workbench' })

vim.api.nvim_create_autocmd('TextYankPost', {
  group = vim.api.nvim_create_augroup('DotfilesYank', { clear = true }),
  callback = function() vim.hl.on_yank({ timeout = 150 }) end,
})

-- Use installed servers; opening a file never installs another runtime.
-- Project settings and virtual environments take precedence over global tools.
local function typescript_root(bufnr, on_dir, legacy)
  local root = vim.fs.root(bufnr, {
    { 'pnpm-lock.yaml', 'yarn.lock', 'package-lock.json', 'bun.lock', 'bun.lockb' },
    { 'package.json', '.git' },
  })
  if not root then return end
  local deno = vim.fs.root(bufnr, { 'deno.json', 'deno.jsonc', 'deno.lock' })
  if deno and #deno >= #root then return end
  local has_tsserver = vim.fn.filereadable(root .. '/node_modules/typescript/lib/tsserver.js') == 1
  if has_tsserver == legacy then on_dir(root) end
end
local brew_tsc = vim.env.HOMEBREW_PREFIX and (vim.env.HOMEBREW_PREFIX .. '/bin/tsc')
local native_tsc = brew_tsc and vim.fn.executable(brew_tsc) == 1 and brew_tsc or 'tsc'
local servers = {
  rust_analyzer = {
    cmd = { 'rust-analyzer' }, filetypes = { 'rust' },
    root_markers = { 'Cargo.toml', 'rust-project.json', '.git' },
  },
  basedpyright = {
    cmd = { 'basedpyright-langserver', '--stdio' }, filetypes = { 'python' },
    root_markers = { 'pyrightconfig.json', 'pyproject.toml', 'requirements.txt', '.git' },
    settings = { basedpyright = { disableOrganizeImports = true, analysis = { diagnosticMode = 'openFilesOnly' } } },
    before_init = function(_, config)
      -- Prefer a local venv; never point all projects at the MLX environment.
      local python = config.root_dir and (config.root_dir .. '/.venv/bin/python')
      if python and vim.fn.executable(python) == 1 then
        config.settings.python = { pythonPath = python }
      end
    end,
  },
  ruff = {
    cmd = { 'ruff', 'server' }, filetypes = { 'python' },
    root_markers = { 'pyproject.toml', 'ruff.toml', '.ruff.toml', '.git' },
    on_attach = function(client) client.server_capabilities.hoverProvider = false end,
  },
  ts_ls = {
    cmd = { 'typescript-language-server', '--stdio' },
    filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
    root_dir = function(bufnr, on_dir) typescript_root(bufnr, on_dir, true) end,
    before_init = function(_, config)
      config.init_options = { hostInfo = 'neovim', tsserver = {
        path = config.root_dir .. '/node_modules/typescript/lib/tsserver.js',
      } }
    end,
  },
  tsc = {
    -- TypeScript 7 exposes LSP natively; the old wrapper needs TS <7.
    cmd = { native_tsc, '--lsp', '--stdio' },
    filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
    root_dir = function(bufnr, on_dir) typescript_root(bufnr, on_dir, false) end,
  },
  bashls = {
    cmd = { 'bash-language-server', 'start' }, filetypes = { 'sh', 'bash' },
    root_markers = { '.git' },
    settings = { bashIde = { globPattern = '*@(.sh|.inc|.bash|.command)' } },
  },
  lua_ls = {
    cmd = { 'lua-language-server' }, filetypes = { 'lua' },
    root_markers = { '.luarc.json', '.luarc.jsonc', '.git' },
  },
  taplo = {
    cmd = { 'taplo', 'lsp', 'stdio' }, filetypes = { 'toml' },
    root_markers = { 'taplo.toml', '.taplo.toml', 'Cargo.toml', 'pyproject.toml', '.git' },
  },
}
for name, config in pairs(servers) do
  vim.lsp.config(name, config)
  if vim.fn.executable(config.cmd[1]) == 1 then vim.lsp.enable(name) end
end
vim.diagnostic.config({ severity_sort = true, float = { border = 'rounded' }, virtual_text = false })
map('n', '<leader>cd', vim.diagnostic.open_float, { desc = 'Line diagnostics' })
map('n', '<leader>cq', vim.diagnostic.setqflist, { desc = 'Project diagnostics' })
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('DotfilesLsp', { clear = true }),
  callback = function(event)
    local opts = { buffer = event.buf }
    map('n', 'gd', vim.lsp.buf.definition, opts)
    map('n', 'gr', vim.lsp.buf.references, opts)
    map('n', 'K', vim.lsp.buf.hover, opts)
    map('n', '<leader>rn', vim.lsp.buf.rename, opts)
    map('n', '<leader>ca', vim.lsp.buf.code_action, opts)
    map('n', '<leader>cf', function()
      vim.lsp.buf.format({ async = true, filter = function(client)
        return vim.bo[event.buf].filetype ~= 'python' or client.name == 'ruff'
      end })
    end, opts)
  end,
})

local local_config = vim.fn.stdpath('config') .. '/local.lua'
if vim.fn.filereadable(local_config) == 1 then dofile(local_config) end
