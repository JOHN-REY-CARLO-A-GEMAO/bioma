#!/usr/bin/env bash
# Downloads the pinned Godot binary and verifies its SHA256 against the
# GitHub release-asset digest (set via env: GODOT_VERSION, GODOT_SHA256).
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.6.2-stable}"
GODOT_SHA256="${GODOT_SHA256:?Set GODOT_SHA256 to the pinned release asset digest}"

mkdir -p godot-bin
cd godot-bin
if [ ! -f godot ]; then
	curl -fsSL --retry 3 -o godot.zip \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_${GODOT_VERSION}_linux.x86_64.zip"
	echo "${GODOT_SHA256}  godot.zip" | sha256sum -c -
	unzip -oq godot.zip
	mv "Godot_${GODOT_VERSION}_linux.x86_64" godot
fi
chmod +x godot
./godot --version
