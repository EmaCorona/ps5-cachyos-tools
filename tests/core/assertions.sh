#!/usr/bin/env bash

assert_file() { [ -f "$1" ] || { echo "assert_file: $1" >&2; return 1; }; }
assert_no_file() { [ ! -e "$1" ] && [ ! -L "$1" ] || { echo "assert_no_file: $1" >&2; return 1; }; }
assert_eq() { [ "${1-}" = "${2-}" ] || { echo "assert_eq: expected='$2' actual='$1'" >&2; return 1; }; }
assert_success() { "$@" >/dev/null 2>&1; }
assert_failure() { ! "$@" >/dev/null 2>&1; }
