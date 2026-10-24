#!/usr/bin/env bash
set -u
root=$1; repo=${CORE_REPO:?}
source "$repo/lib/modules/fan.sh"
module_fan_run "$root"
