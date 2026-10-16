#!/bin/sh
# Build bin/autolith-analytics from source.
# Requires: SBCL + Quicklisp, with the autolith-analytics system visible to ASDF
# (make install-links symlinks it into ~/quicklisp/local-projects).
set -e
DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$DIR"
exec sbcl --noinform --disable-debugger --load build.lisp
