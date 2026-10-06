# shellcheck shell=bash
# Container runtime interface. Everything the kit needs from a container runtime
# goes through these rt_* functions, so adding LXC later means a second
# implementation of this file, not changes across the kit.
#
# This implementation: apple/container (the `container` CLI), macOS.

AIPA_RUNTIME_BIN="${AIPA_RUNTIME_BIN:-container}"

rt_require() {
  command -v "$AIPA_RUNTIME_BIN" >/dev/null 2>&1 \
    || die "apple/container is not installed (no '$AIPA_RUNTIME_BIN' command): https://github.com/apple/container/releases"
  if ! "$AIPA_RUNTIME_BIN" system status >/dev/null 2>&1; then
    die "the container service is not running. Start it with: container system start --enable-kernel-install"
  fi
}

# Prints running, stopped or absent.
rt_container_state() {  # <name>
  local json state
  if ! json=$("$AIPA_RUNTIME_BIN" inspect "$1" 2>/dev/null); then
    echo absent
    return 0
  fi
  state=$(printf '%s' "$json" | jq -r '.[0].status.state // empty' 2>/dev/null || true)
  case "$state" in
    running) echo running ;;
    "") echo absent ;;
    *) echo stopped ;;
  esac
}

rt_image_exists() { "$AIPA_RUNTIME_BIN" image inspect "$1" >/dev/null 2>&1; }

# Content digests: an image's, and the one a container was created from. They
# differ when the image was rebuilt after the container was created.
rt_image_digest() { "$AIPA_RUNTIME_BIN" image inspect "$1" 2>/dev/null | jq -r '.[0].configuration.descriptor.digest // empty'; }
rt_container_image_digest() { "$AIPA_RUNTIME_BIN" inspect "$1" 2>/dev/null | jq -r '.[0].configuration.image.descriptor.digest // empty'; }

rt_build_image() {  # <ref> <context-dir> <containerfile> <no-cache:0|1> [build-arg ...]
  local ref=$1 ctx=$2 file=$3 nocache=$4 args=() kv
  shift 4
  [ "$nocache" = 1 ] && args+=(--no-cache)
  for kv in "$@"; do args+=(--build-arg "$kv"); done
  "$AIPA_RUNTIME_BIN" build --progress plain --tag "$ref" --file "$file" ${args[@]+"${args[@]}"} "$ctx"
}

rt_volume_ensure() {  # <name>
  "$AIPA_RUNTIME_BIN" volume inspect "$1" >/dev/null 2>&1 \
    || "$AIPA_RUNTIME_BIN" volume create "$1" >/dev/null
}

# Create a stopped container. Mounts are "host:container[:ro]" bind mounts or
# "volume-name:container" named volumes.
rt_create() {  # <name> <image> <label> <mount>...
  local name=$1 image=$2 label=$3 args=() m
  shift 3
  for m in "$@"; do args+=(--volume "$m"); done
  "$AIPA_RUNTIME_BIN" create --name "$name" --label "$label" ${args[@]+"${args[@]}"} "$image" >/dev/null
}

rt_start() { "$AIPA_RUNTIME_BIN" start "$1" >/dev/null; }
rt_stop() { "$AIPA_RUNTIME_BIN" stop "$1" >/dev/null; }
rt_delete() { "$AIPA_RUNTIME_BIN" delete "$1" >/dev/null; }

# `container exec --user` does not set HOME, so callers pass it.
# Run a command in a running container, without a terminal.
rt_exec() {  # <name> <user> <home> <workdir> <cmd...>
  local name=$1 user=$2 home=$3 dir=$4
  shift 4
  "$AIPA_RUNTIME_BIN" exec --user "$user" --env "HOME=$home" --workdir "$dir" "$name" "$@"
}

# Same, with stdin connected (for piping content into the container).
rt_exec_stdin() {  # <name> <user> <home> <workdir> <cmd...>
  local name=$1 user=$2 home=$3 dir=$4
  shift 4
  "$AIPA_RUNTIME_BIN" exec --interactive --user "$user" --env "HOME=$home" --workdir "$dir" "$name" "$@"
}

# Replace this process with an interactive terminal session, optionally
# passing an env file (used for the harness credentials).
rt_exec_tty() {  # <name> <user> <home> <workdir> <env-file|""> <cmd...>
  local name=$1 user=$2 home=$3 dir=$4 envf=$5 envargs=()
  shift 5
  [ -n "$envf" ] && envargs=(--env-file "$envf")
  exec "$AIPA_RUNTIME_BIN" exec --interactive --tty --user "$user" --env "HOME=$home" \
    --env "TERM=${TERM:-xterm-256color}" --workdir "$dir" ${envargs[@]+"${envargs[@]}"} "$name" "$@"
}
