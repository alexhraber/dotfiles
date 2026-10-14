# Installer sets DOTFILES_GROUPS so optional groups stay optional.
groups = ENV.fetch("DOTFILES_GROUPS", "terminal,git,codex,workspace").split(",")

if groups.include?("terminal")
  cask "ghostty"
  cask "font-jetbrains-mono-nerd-font"
  %w[starship fastfetch fzf zoxide direnv mise zsh-autosuggestions
     zsh-syntax-highlighting eza bat ripgrep fd lazygit neovim btop].each { |name| brew name }
end
brew "git-delta" if groups.include?("git") || groups.include?("terminal")
cask "codex" if groups.include?("codex")
# TOML validation in doctor and the test suite needs Python 3.11+.
brew "python@3.14"

brew "podman" if groups.include?("workspace")
