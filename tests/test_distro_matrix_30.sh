#!/bin/bash
# 3.0 E2: distro matrix (gate tools distro-matrix.sh) on the installer copy: sim rows whose images are cached, qemu
# rows where qemu-aarch64 binfmt (or an arm64 host) is there; others SKIP with the reason. No download unless
# SARM_MATRIX_FETCH=1; SARM_MATRIX_FAST=1 leaves out install rows (they reach package indexes and keyserver). Internal.
. "$(dirname "$0")/paths.sh"
DM=$SARM_GATES/distro-matrix.sh
[ -f "$DM" ] || { echo "SKIP distro matrix: $DM not found"; exit 0; }
o=(--cached-only); [ "${SARM_MATRIX_FETCH:-0}" = 1 ] && o=()
[ "${SARM_MATRIX_FAST:-0}" = 1 ] && o+=(--fast)
rc=0
for b in sim qemu; do SARM_INST=$SARM_INST bash "$DM" --backend $b "${o[@]}" || rc=1; done
exit $rc
