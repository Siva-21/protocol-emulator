#!/usr/bin/env bash
# Shell in the pe-verif image (IIC-OSIC-TOOLS + verification extras, see README.md).
#
#   verification/docker/pe-shell.sh               interactive bash
#   verification/docker/pe-shell.sh <cmd> [args]  run one command, e.g. from the repo root:
#       verification/docker/pe-shell.sh scripts/check_rtl_frontend.sh
#
# $DESIGNS is mounted at /foss/designs; this repo is expected below it
# (default: /foss/designs/protocol-emulator). The shell or command starts in the
# container folder that matches the host's current folder when that is inside
# $DESIGNS (e.g. repo root -> /foss/designs/protocol-emulator), so relative
# paths work as on the host; elsewhere it starts in /foss/designs.
# Runs as your UID/GID, so files written there stay yours. The container is
# removed on exit (--rm); a second call while a shell is open joins the same
# container (docker exec), also in the folder matching the current one.
# Every variable below can be overridden from the environment.
set -euo pipefail

DESIGNS="${DESIGNS:-$HOME/edatools/designs}"
# Published on GHCR; a local build under the same name works too (README.md).
IMAGE="${IMAGE:-ghcr.io/siva-21/pe-verif:2026.10}"
# PDK for the session. The image defaults to ihp-sg13g2; its startup derives
# PDKPATH, STD_CELL_LIBRARY, KLAYOUT_PATH and SPICE_USERINIT_DIR from $PDK
# (under $PDK_ROOT=/foss/pdks), so no personal $DESIGNS/.designinit is needed.
PDK="${PDK:-ihp-sg13cmos5l}"
CONTAINER_NAME="${CONTAINER_NAME:-pe-verif_shell_uid_$(id -u)}"
CONTAINER_USER="${CONTAINER_USER:-$(id -u)}"
CONTAINER_GROUP="${CONTAINER_GROUP:-$(id -g)}"

if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
	echo "[ERROR] Image $IMAGE not found. Pull it with:" >&2
	echo "        docker pull $IMAGE" >&2
	echo "        or build it (from the repo root): docker build -t $IMAGE verification/docker" >&2
	exit 1
fi
if [ ! -d "$DESIGNS" ]; then
	echo "[ERROR] DESIGNS directory $DESIGNS does not exist (set DESIGNS=...)." >&2
	exit 1
fi

tty_flags=(-i)
[ -t 0 ] && [ -t 1 ] && tty_flags=(-it)

# Container folder matching the host's current folder: /foss/designs/<path> if
# the current folder is $DESIGNS or below it, else /foss/designs. Symlinks are
# resolved on both sides (pwd -P).
designs_real="$(cd "$DESIGNS" && pwd -P)"
here_real="$(pwd -P)"
case "$here_real/" in
	"$designs_real"/*) WORKDIR="/foss/designs${here_real#"$designs_real"}" ;;
	*)                 WORKDIR=/foss/designs ;;
esac

state="$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)"
if [ "$state" = "true" ]; then
	# Shell already open: join it. docker exec skips the entrypoint, so call it
	# explicitly; it sets up PATH/env and the nss_wrapper user, as for docker run.
	[ $# -gt 0 ] || set -- /bin/bash
	exec docker exec "${tty_flags[@]}" -w "$WORKDIR" "$CONTAINER_NAME" \
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
	-e "PDK=$PDK"
	--security-opt seccomp=unconfined
	-v "$DESIGNS:/foss/designs:rw"
	-w "$WORKDIR")
if [ $# -gt 0 ]; then
	exec docker run "${args[@]}" "$IMAGE" -s "$@"
fi
exec docker run "${args[@]}" "$IMAGE" -s /bin/bash
