# Shared setup for the bats tests: an isolated HOME and config dir, and a bin
# dir of fakes put first on PATH so no test touches the real container
# runtime, launchd or GitHub.
setup_isolated() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export AIPA_CONFIG_HOME="$HOME/.config/ai-proj-arch"
  export AIPA_LOG_DIR="$HOME/logs"
  FAKES="$BATS_TEST_TMPDIR/fakes"
  mkdir -p "$HOME" "$FAKES"
  export PATH="$FAKES:$PATH"
  export FAKE_LOG="$BATS_TEST_TMPDIR/fake.log"
  : > "$FAKE_LOG"
}

# Write an executable fake command into the fakes dir.
fake() {  # <name>  (script body on stdin)
  { echo '#!/bin/bash'; cat; } > "$FAKES/$1"
  chmod +x "$FAKES/$1"
}

load_lib() {
  # shellcheck source=../lib/aipa/common.sh
  . "$ROOT/lib/aipa/common.sh"
  # shellcheck source=../lib/aipa/runtime.sh
  . "$ROOT/lib/aipa/runtime.sh"
  # shellcheck source=../lib/aipa/broker.sh
  . "$ROOT/lib/aipa/broker.sh"
}

write_project() {  # <project> <repo> <main-dir>
  mkdir -p "$AIPA_CONFIG_HOME/projects/$1"
  printf 'AIPA_REPO=%s\nAIPA_MAIN_DIR=%s\n' "$2" "$3" > "$AIPA_CONFIG_HOME/projects/$1/project.env"
}
