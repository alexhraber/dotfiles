# Existing local-model installations; invocation is always explicit.
# MLX stays in its own virtual environment instead of replacing shell Python.
mlx() {
  local command_path="${MLX_ENV:-$HOME/.venvs/mlx}/bin/mlx_lm.generate"
  [[ -x $command_path ]] || { print -u2 "mlx: executable missing: $command_path"; return 1; }
  "$command_path" "$@"
}
mlxchat() {
  local command_path="${MLX_ENV:-$HOME/.venvs/mlx}/bin/mlx_lm.chat"
  [[ -x $command_path ]] || { print -u2 "mlxchat: executable missing: $command_path"; return 1; }
  "$command_path" "$@"
}
mlxserve() {
  local command_path="${MLX_ENV:-$HOME/.venvs/mlx}/bin/mlx_lm.server"
  [[ -x $command_path ]] || { print -u2 "mlxserve: executable missing: $command_path"; return 1; }
  "$command_path" --host 127.0.0.1 "$@"
}
cxlocal() {
  (( $+commands[codex] && $+commands[ollama] )) || { print -u2 'cxlocal: codex and ollama are required'; return 1; }
  command codex --oss --local-provider ollama --model "${CODEX_LOCAL_MODEL:-qwen3-coder:30b}" "$@"
}
