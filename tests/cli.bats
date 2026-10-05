#!/usr/bin/env bats
load helpers

setup() {
  setup_isolated
  AIPA="$ROOT/bin/aipa"
  fake container <<'EOF2'
echo "container $*" >> "$FAKE_LOG"
[ "$1" = system ] && exit 0
[ "$1" = inspect ] && exit 1
exit 0
EOF2
}

@test "help, version and an unknown command" {
  run "$AIPA" help;    [ "$status" -eq 0 ]; [[ "$output" == *"aipa shell <project>"* ]]
  run "$AIPA" version; [ "$output" = "$(tr -d '[:space:]' < "$ROOT/VERSION")" ]
  run "$AIPA" frobnicate; [ "$status" -eq 2 ]
}

@test "commands need a set-up project" {
  run "$AIPA" start nosuch;  [ "$status" -ne 0 ]; [[ "$output" == *"not set up"* ]]
  run "$AIPA" status nosuch; [ "$status" -ne 0 ]
  run "$AIPA" start BAD;     [ "$status" -ne 0 ]; [[ "$output" == *"invalid project name"* ]]
}

@test "create requires --repo for a new project and refuses a different repo later" {
  run "$AIPA" create yb; [ "$status" -ne 0 ]; [[ "$output" == *"--repo"* ]]
  write_project yb dpeckham/yawnbooks /tmp/main
  run "$AIPA" create yb --repo someone/else; [ "$status" -ne 0 ]; [[ "$output" == *"already uses dpeckham/yawnbooks"* ]]
}

@test "start refuses when the container does not exist" {
  write_project yb dpeckham/yawnbooks /tmp/main
  run "$AIPA" start yb; [ "$status" -ne 0 ]; [[ "$output" == *"no container"* ]]
}

@test "the container runtime must be installed and running" {
  rm "$FAKES/container"
  fake container <<'EOF2'
[ "$1" = system ] && exit 1
EOF2
  write_project yb dpeckham/yawnbooks /tmp/main
  run "$AIPA" start yb; [ "$status" -ne 0 ]; [[ "$output" == *"container system start"* ]]
}
