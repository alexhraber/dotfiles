# Homebrew Ghidra/JDK discovery. Preserve explicit user choices.
if [[ -n ${HOMEBREW_PREFIX:-} ]]; then
  if [[ -z ${GHIDRA_INSTALL_DIR:-} && -x $HOMEBREW_PREFIX/opt/ghidra/libexec/support/analyzeHeadless ]]; then
    export GHIDRA_INSTALL_DIR="$HOMEBREW_PREFIX/opt/ghidra/libexec"
  fi
  if [[ -z ${JAVA_HOME:-} && -x $HOMEBREW_PREFIX/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java ]]; then
    export JAVA_HOME="$HOMEBREW_PREFIX/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
  fi
fi
