# Explicit container shell/command; never creates or starts a VM.
# Usage: cws <fully-qualified-image[:tag|@digest]> [command ...]
cws() {
  (( $# >= 1 )) || { print -u2 'usage: cws <image> [command ...]'; return 2; }
  (( $+commands[podman] )) || { print -u2 'cws: install the workspace group'; return 1; }
  [[ ${PWD:A} != ${HOME:A} && ${PWD:A} != / ]] || {
    print -u2 'cws: enter a project directory before mounting it'; return 1;
  }
  command podman info >/dev/null 2>&1 || {
    print -u2 'cws: Podman is unavailable. Start an existing machine headlessly with --quiet --no-info; never use debug logging.'
    return 1
  }
  local image="$1"
  shift
  local -a flags=(--rm --interactive --userns=keep-id --cap-drop=all
    --security-opt=no-new-privileges --security-opt=label=disable
    --mount "type=bind,source=$PWD,destination=/workspace" --workdir=/workspace)
  [[ -t 0 && -t 1 ]] && flags+=(--tty)
  # Only the project is shared. Host auth directories, SSH agents, model stores
  # and the container engine socket are not mounted.
  command podman run "${flags[@]}" "$image" "$@"
}
