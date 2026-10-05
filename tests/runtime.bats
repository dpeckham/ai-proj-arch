#!/usr/bin/env bats
load helpers

setup() {
  setup_isolated
  load_lib
  fake container <<'EOF2'
echo "container $*" >> "$FAKE_LOG"
case "$1" in
  inspect)
    case "$2" in
      up) echo '[{"status":{"state":"running"}}]' ;;
      down) echo '[{"status":{"state":"stopped"}}]' ;;
      *) exit 1 ;;
    esac ;;
  volume) [ "$2" = inspect ] && [ "$3" = existing ] && exit 0; [ "$2" = inspect ] && exit 1; exit 0 ;;
esac
EOF2
}

@test "container state maps to running, stopped or absent" {
  [ "$(rt_container_state up)" = running ]
  [ "$(rt_container_state down)" = stopped ]
  [ "$(rt_container_state nope)" = absent ]
}

@test "create passes the label and every mount" {
  rt_create aipa-x img:1 ai-proj-arch.project=x /h/main:/work/main /h/run:/run/aipa:ro vol:/home/agent
  grep -q -- "create --name aipa-x --label ai-proj-arch.project=x --volume /h/main:/work/main --volume /h/run:/run/aipa:ro --volume vol:/home/agent img:1" "$FAKE_LOG"
}

@test "build passes build args, and --no-cache only when asked" {
  rt_build_image ref:1 /ctx /ctx/Containerfile 0 A=1 B=2
  grep -q -- "build --progress plain --tag ref:1 --file /ctx/Containerfile --build-arg A=1 --build-arg B=2 /ctx" "$FAKE_LOG"
  ! grep -q -- --no-cache "$FAKE_LOG"
  rt_build_image ref:1 /ctx /ctx/Containerfile 1
  grep -q -- "build --progress plain --tag ref:1 --file /ctx/Containerfile --no-cache /ctx" "$FAKE_LOG"
}

@test "volumes are created only when missing" {
  rt_volume_ensure existing
  ! grep -q "volume create existing" "$FAKE_LOG"
  rt_volume_ensure fresh
  grep -q "volume create fresh" "$FAKE_LOG"
}

@test "exec sets HOME for the user" {
  rt_exec c agent /home/agent /work echo hi
  grep -q -- "exec --user agent --env HOME=/home/agent --workdir /work c echo hi" "$FAKE_LOG"
}
