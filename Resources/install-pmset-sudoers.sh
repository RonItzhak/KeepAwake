#!/bin/bash
# Writes /etc/sudoers.d/keepawake so admin users can run /usr/bin/pmset without a
# password. Must run as root (pkg postinstall, or a one-time admin dialog).
set -euo pipefail

if [ "$(/usr/bin/id -u)" -ne 0 ]; then
  echo "must run as root" >&2
  exit 1
fi

DEST=/etc/sudoers.d/keepawake
TMP=$(/usr/bin/mktemp)
trap '/bin/rm -f "$TMP"' EXIT

/bin/echo '%admin ALL=(root) NOPASSWD: /usr/bin/pmset' > "$TMP"
/bin/chmod 0440 "$TMP"
/usr/sbin/visudo -cf "$TMP"
/bin/mv "$TMP" "$DEST"
trap - EXIT
/bin/chmod 0440 "$DEST"
