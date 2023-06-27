#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

export TMPDIR=/tmp

DEVICE_FAMILY="felix"
REV="13-felix"

args=(
    --cache-search-path ../../../
    --ref-type branch
    --out "repo-${DEVICE_FAMILY}-${REV}.json"
    "https://github.com/GrapheneOS/kernel_manifest-${DEVICE_FAMILY}"
    "${REV}"
    "$@"
)

../../../scripts/mk_repo_file.py "${args[@]}"
