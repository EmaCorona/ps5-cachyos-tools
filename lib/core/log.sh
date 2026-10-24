#!/usr/bin/env bash
set -u

core_log() { printf 'ps5-cachyos-tools: %s\n' "$*" >&2; }
core_die() { core_log "errore: $*"; return 1; }
