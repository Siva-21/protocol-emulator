#!/usr/bin/env bash
# Browser desktop (noVNC) in the pe-verif image, reachable only from this machine.
#
#   verification/docker/pe-desktop.sh         start (or reuse) the desktop
#   verification/docker/pe-desktop.sh stop    stop and remove the desktop container
#   verification/docker/pe-desktop.sh url     print the login URL (contains the password)
#
# Then open http://localhost:$WEB_PORT and enter the password from $PASSWORD_FILE.
#
# Security:
# - The web UI is published on 127.0.0.1:$WEB_PORT only; the raw VNC port
#   (5901) is not published.
# - The password replaces the image default. It lives in $PASSWORD_FILE
#   (mode 600) and is generated on first use: 8 random letters/digits (VNC
#   uses only the first 8 characters). It is passed to the container through
#   the environment, not on the command line.
# Every variable below can be overridden from the environment.
set -euo pipefail

DESIGNS="${DESIGNS:-$HOME/edatools/designs}"
# Published on GHCR; a local build under the same name works too (README.md).
IMAGE="${IMAGE:-ghcr.io/siva-21/pe-verif:2026.10}"
# PDK for the session. The image defaults to ihp-sg13g2; its startup derives
# PDKPATH, STD_CELL_LIBRARY, KLAYOUT_PATH and SPICE_USERINIT_DIR from $PDK
# (under $PDK_ROOT=/foss/pdks), so no personal $DESIGNS/.designinit is needed.
PDK="${PDK:-ihp-sg13cmos5l}"
WEB_PORT="${WEB_PORT:-8080}"
PASSWORD_FILE="${PASSWORD_FILE:-$HOME/edatools/.vnc_password}"
CONTAINER_NAME="${CONTAINER_NAME:-pe-verif_xvnc_uid_$(id -u)}"
CONTAINER_USER="${CONTAINER_USER:-$(id -u)}"
CONTAINER_GROUP="${CONTAINER_GROUP:-$(id -g)}"

if [ "${1:-}" = "stop" ]; then
	# docker rm -f succeeds even for a missing container, so check first.
	if docker inspect "$CONTAINER_NAME" > /dev/null 2>&1; then
		docker rm -f "$CONTAINER_NAME" > /dev/null
		echo "[INFO] Stopped and removed $CONTAINER_NAME."
	else
		echo "[INFO] $CONTAINER_NAME is not present."
	fi
	exit 0
fi

# Password file: create if missing, always enforce mode 600.
umask 077
mkdir -p "$(dirname "$PASSWORD_FILE")"
if [ ! -s "$PASSWORD_FILE" ]; then
	tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8 > "$PASSWORD_FILE"
	echo "[INFO] Generated a new VNC password in $PASSWORD_FILE."
fi
chmod 600 "$PASSWORD_FILE"
VNC_PW="$(tr -dc 'A-Za-z0-9' < "$PASSWORD_FILE" | head -c 8)"
if [ "${#VNC_PW}" -ne 8 ]; then
	echo "[ERROR] $PASSWORD_FILE must hold 8 letters/digits. Delete it to generate a new one." >&2
	exit 1
fi
export VNC_PW

if [ "${1:-}" = "url" ]; then
	echo "http://localhost:${WEB_PORT}/?password=${VNC_PW}"
	exit 0
fi
if [ -n "${1:-}" ]; then
	echo "Usage: $0 [stop|url]" >&2
	exit 2
fi

state="$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)"
if [ "$state" = "true" ]; then
	echo "[INFO] $CONTAINER_NAME is already running."
elif [ -n "$state" ]; then
	echo "[INFO] Restarting existing container $CONTAINER_NAME ..."
	docker start "$CONTAINER_NAME" > /dev/null
else
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
	# Same options as the IIC-OSIC-TOOLS start_vnc.sh (seccomp, keyboard
	# layout, designs mount), with the web port bound to localhost only.
	docker run -d --name "$CONTAINER_NAME" \
		--user "$CONTAINER_USER:$CONTAINER_GROUP" \
		--security-opt seccomp=unconfined \
		-p "127.0.0.1:${WEB_PORT}:80" \
		-e VNC_PW \
		-e "PDK=$PDK" \
		-e "XKB_KEYBOARD_LAYOUT=${XKB_KEYBOARD_LAYOUT:-us}" \
		-e "XKB_KEYBOARD_VARIANT=${XKB_KEYBOARD_VARIANT:-}" \
		-v "$DESIGNS:/foss/designs:rw" \
		"$IMAGE" > /dev/null
fi

# The container must stay up for a few seconds (startup errors exit early).
for _ in 1 2 3; do
	sleep 1
	if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" != "true" ]; then
		echo "[ERROR] $CONTAINER_NAME stopped during startup. Last log lines:" >&2
		docker logs --tail 20 "$CONTAINER_NAME" 2>&1 | sed 's/^/    /' >&2
		exit 1
	fi
done
echo "[INFO] Desktop: http://localhost:${WEB_PORT}  (password: ${PASSWORD_FILE})"
echo "[INFO] Stop it with: $0 stop"
