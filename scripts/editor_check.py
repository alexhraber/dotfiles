#!/usr/bin/env python3
"""Exercise installed Neovim servers using disposable projects (dev group)."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

LUA = r'''
local cases = {
  { 'main.py', { 'basedpyright', 'ruff' } },
  { 'main.ts', { 'tsc' } },
  { 'main.lua', { 'lua_ls' } },
  { 'main.sh', { 'bashls' } },
  { 'pyproject.toml', { 'taplo' } },
}
if vim.fn.executable('rust-analyzer') == 1 then
  table.insert(cases, { 'src/main.rs', { 'rust_analyzer' } })
else
  print('SKIP Rust LSP: rust-analyzer component is not installed')
end
for _, case in ipairs(cases) do
  vim.cmd.edit(case[1])
  local buf = vim.api.nvim_get_current_buf()
  for _, expected in ipairs(case[2]) do
    local ready = vim.wait(12000, function()
      local clients = vim.lsp.get_clients({ bufnr = buf, name = expected })
      return #clients > 0 and clients[1].initialized
    end, 100)
    assert(ready, 'LSP failed to attach: ' .. expected .. ' for ' .. case[1])
    print('PASS ' .. expected .. ' attached to ' .. case[1])
  end
  if case[1] == 'main.py' then
    local pyright = vim.lsp.get_clients({bufnr=buf,name='basedpyright'})[1]
    assert(pyright.settings.python.pythonPath == vim.fn.getcwd() .. '/.venv/bin/python')
    local ruff = vim.lsp.get_clients({bufnr=buf,name='ruff'})[1]
    local result, err = ruff:request_sync('textDocument/formatting', {
      textDocument={uri=vim.uri_from_bufnr(buf)},options={tabSize=4,insertSpaces=true}
    }, 5000, buf)
    assert(result and not result.err and not err, 'Ruff formatting failed')
    vim.lsp.util.apply_text_edits(result.result,buf,ruff.offset_encoding)
    assert(vim.api.nvim_buf_get_lines(buf,0,1,false)[1] == 'def f(x: int) -> int:')
    print('PASS Python project venv selection and Ruff formatting')
  end
  if case[1] == 'main.ts' then
    local tsc = vim.lsp.get_clients({bufnr=buf,name='tsc'})[1]
    local result, err = tsc:request_sync('textDocument/hover', {
      textDocument={uri=vim.uri_from_bufnr(buf)},position={line=0,character=8}
    }, 10000, buf)
    assert(result and result.result and not result.err and not err, 'TypeScript hover failed')
    print('PASS TypeScript native LSP hover')
  end
end
'''


def main():
    with tempfile.TemporaryDirectory(prefix='dotfiles-editor-') as folder:
        root = Path(folder).resolve()
        (root / '.git').mkdir()
        (root / 'src').mkdir()
        files = {
            'pyproject.toml': '[project]\nname="smoke"\nversion="0.1.0"\n',
            'package.json': '{"name":"smoke","private":true}',
            'tsconfig.json': '{"compilerOptions":{"strict":true}}',
            'Cargo.toml': '[package]\nname="smoke"\nversion="0.1.0"\nedition="2024"\n',
            'src/main.rs': 'fn main() { println!("smoke"); }\n',
            'main.py': 'def f( x:int)->int:\n return x+1\n',
            'main.ts': 'const message: string = "smoke";\nconsole.log(message);\n',
            'main.lua': 'local message = "smoke"\nprint(message)\n',
            'main.sh': '#!/usr/bin/env bash\nprintf "%s\\n" smoke\n',
            'check.lua': LUA,
        }
        for name, content in files.items():
            (root / name).write_text(content)
        subprocess.run([sys.executable, '-m', 'venv', '--without-pip', str(root / '.venv')], check=True)
        command = 'lua local ok,err=pcall(dofile,' + json.dumps(str(root / 'check.lua')) + '); '
        command += 'for _,client in ipairs(vim.lsp.get_clients()) do client:stop() end; '
        command += 'vim.wait(1000,function() return #vim.lsp.get_clients()==0 end,50); '
        command += 'if ok then vim.cmd("qa!") else print(err); vim.cmd("cquit") end'
        return subprocess.run(['nvim', '--headless', '-c', command], cwd=root, timeout=100).returncode


if __name__ == '__main__':
    sys.exit(main())
