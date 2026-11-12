#!/usr/bin/env bash
# Shell in the pe-verif image (IIC-OSIC-TOOLS + verification extras, see README.md).
#
#   verification/docker/pe-shell.sh               interactive bash
#   verification/docker/pe-shell.sh <cmd> [args]  run one command, e.g.
#       verification/docker/pe-shell.sh make -C /foss/designs/protocol-emulator/test
#
# $DESIGNS is mounted at /foss/designs; this repo is expected below it
# (default: /foss/designs/protocol-emulator). Runs as your UID/GID, so files
# written there stay yours. The container is removed on exit (--rm); a second
# call while a shell is open joins the same container (docker exec).
# Every variable below can be overridden from the environment.
set -euo pipefail

DESIGNS="${DESIGNS:-$HOME/edatools/designs}"
# After the first GHCR publish: IMAGE=ghcr.io/siva-21/pe-verif:2026.10
IMAGE="${IMAGE:-pe-verif:2026.10}"
CONTAINER_NAME="${CONTAINER_NAME:-pe-verif_shell_uid_$(id -u)}"
CONTAINER_USER="${CONTAINER_USER:-$(id -u)}"
CONTAINER_GROUP="${CONTAINER_GROUP:-$(id -g)}"

if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
	echo "[ERROR] Image $IMAGE not found. Build it (from the repo root) with:" >&2
	echo "        docker build -t $IMAGE verification/docker" >&2
	exit 1
fi
if [ ! -d "$DESIGNS" ]; then
	echo "[ERROR] DESIGNS directory $DESIGNS does not exist (set DESIGNS=...)." >&2
	exit 1
fi

tty_flags=(-i)
[ -t 0 ] && [ -t 1 ] && tty_flags=(-it)

state="$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)"
if [ "$state" = "true" ]; then
	# Shell already open: join it. docker exec skips the entrypoint, so call it
	# explicitly; it sets up PATH/env and the nss_wrapper user, as for docker run.
	[ $# -gt 0 ] || set -- /bin/bash
	exec docker exec "${tty_flags[@]}" -w /foss/designs "$CONTAINER_NAME" \
		/dockerstartup/scripts/ui_startup.sh -s "$@"
elif [ -n "$state" ]; then
	echo "[ERROR] A stopped container named $CONTAINER_NAME exists (left by an older start script)." >&2
	echo "        Remove it with: docker rm $CONTAINER_NAME" >&2
	exit 1
fi

# Same options as the IIC-OSIC-TOOLS start_shell.sh (DISPLAY default, seccomp,
# designs mount), minus the persistent container.
args=(--rm "${tty_flags[@]}" --name "$CONTAINER_NAME"
	--user "$CONTAINER_USER:$CONTAINER_GROUP"
	-e "DISPLAY=${DISPLAY:-:0}"
	--security-opt seccomp=unconfined
	-v "$DESIGNS:/foss/designs:rw")
if [ $# -gt 0 ]; then
	exec docker run "${args[@]}" "$IMAGE" -s "$@"
fi
exec docker run "${args[@]}" "$IMAGE" -s /bin/bash
