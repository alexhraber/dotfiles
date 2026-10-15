# Homebrew preserves HOMEBREW_* variables when dispatching Bundle.
groups = ENV.fetch("HOMEBREW_DOTFILES_GROUPS", "terminal,git,codex,workspace,dev,reverse,apple,infra,ai,apps,macos").split(",")

if groups.include?("terminal")
  cask "ghostty"
  cask "font-jetbrains-mono-nerd-font"
  %w[starship fastfetch fzf zoxide direnv mise zsh-autosuggestions
     zsh-syntax-highlighting eza bat ripgrep fd lazygit neovim btop tmux].each { |name| brew name }
end
brew "git-delta" if groups.include?("git") || groups.include?("terminal")
cask "codex" if groups.include?("codex")
# TOML validation in doctor and the test suite needs Python 3.11+.
brew "python@3.14"

brew "podman" if groups.include?("workspace")

if groups.include?("dev")
  # Project runtimes stay under mise/rustup/uv; these are workstation tools.
  %w[gh jq yq uv cargo-binstall shellcheck shfmt actionlint hadolint
     ruff basedpyright typescript typescript-language-server bash-language-server
     lua-language-server taplo cmake ninja pkgconf ffmpeg].each { |name| brew name }
end
# REA's free native analysis engine; Homebrew supplies its JDK dependency.
brew "ghidra" if groups.include?("reverse")
brew "mas" if groups.include?("apple") && OS.mac?
if groups.include?("infra")
  %w[kubernetes-cli helm k9s opentofu grpcurl].each { |name| brew name }
end
if groups.include?("ai")
  brew "ollama" # Models and service startup are explicit, never login hooks.
  brew "mlx" if OS.mac? && Hardware::CPU.arm?
end
if groups.include?("apps")
  # A manually installed, system-owned Chrome can require sudo even for adopt.
  # Respect that existing app. Fresh machines still install the declared cask;
  # once Brew-managed, it remains in the bundle for subsequent maintenance.
  chrome_app = OS.mac? && File.directory?("/Applications/Google Chrome.app")
  chrome_managed = File.directory?(File.join(HOMEBREW_PREFIX.to_s, "Caskroom/google-chrome/.metadata"))
  cask "google-chrome" unless chrome_app && !chrome_managed
end
