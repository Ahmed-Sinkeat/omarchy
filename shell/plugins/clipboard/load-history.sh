#!/bin/bash

# Streams legacy history through migration before handing bounded JSON to QML.
#
#   load-history.sh <path> <max-bytes>
#
# Prints the history and exits 0; an absent file prints []. A file the overlay
# could not have written itself -- a symlink, a FIFO or other non-regular file,
# invalid JSON, or JSON that is not an array -- is
# renamed to <path>.rejected-<time> and prints [], so its bytes stay with the
# user and are never saved over. Exit 3 means history exists but could not be
# read or renamed: the overlay must not write over it.

set -o pipefail

path=${1:?usage: load-history.sh <path> <max-bytes>}
ceiling=${2:?usage: load-history.sh <path> <max-bytes>}

tmp=$(mktemp) || exit 3
trap 'rm -f "$tmp"' EXIT

reject() {
  local backup="$path.rejected-$(date +%Y%m%d-%H%M%S-%N)"
  mv -- "$path" "$backup" || exit 3
  printf 'clipboard: history set aside at %s\n' "$backup" >&2
  printf '[]'
  exit 0
}

if [[ ! -e $path && ! -L $path ]]; then
  printf '[]'
  exit 0
fi

[[ -L $path || ! -f $path ]] && reject

[[ -r $path ]] || exit 3

# O_NOFOLLOW and O_NONBLOCK in the helper cover path swaps, too. A legacy
# history may exceed the output ceiling; its text is streamed into files.
timeout -k 1 30 python3 "$(dirname -- "${BASH_SOURCE[0]}")/migrate-history.py" "$path" "$ceiling" >"$tmp"
status=$?
if (( status == 2 )); then
  reject
elif (( status != 0 )); then
  exit 3
fi

cat -- "$tmp"
