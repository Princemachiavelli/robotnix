#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

../../modules/apv/update-carrierlist.sh

_KERNEL_PREFIX=${KERNEL_PREFIX:-kernel/google}

REFTYPE="$1"; shift;

args=(
    --cache-search-path ../../
    --ref-type "$REFTYPE"
    --project-fetch-submodules "${_KERNEL_PREFIX}/redbull"
    --project-fetch-submodules "${_KERNEL_PREFIX}/raviole"
    --project-fetch-submodules "${_KERNEL_PREFIX}/pantah"
    --project-fetch-submodules "${_KERNEL_PREFIX}/tangorpro"
    --project-fetch-submodules "${_KERNEL_PREFIX}/felix"
    "https://github.com/GrapheneOS/platform_manifest"
    "$@"
)

export TMPDIR=/tmp

../../scripts/mk_repo_file.py "${args[@]}"
