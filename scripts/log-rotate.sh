#!/usr/bin/env bash
# log-rotate.sh — M7: .out file rotation for long-running tools
#
# Rotates .out files in loot/ that exceed 1MB.
# Keeps max 3 rotations (.out, .out.1, .out.2, .out.3).
# Called by monitor agent heartbeat to prevent unbounded log growth.
#
# Usage:
#   ./scripts/log-rotate.sh [loot_dir]
#
# Default loot_dir: ./loot/

set -euo pipefail

LOOT_DIR="${1:-./loot}"
MAX_SIZE_BYTES=$((1 * 1024 * 1024))  # 1MB
MAX_ROTATIONS=3
ROTATED=0

if [ ! -d "$LOOT_DIR" ]; then
    echo "Loot directory not found: $LOOT_DIR"
    exit 0
fi

# Find all .out files exceeding 1MB
while IFS= read -r -d '' outfile; do
    file_size=$(stat -c%s "$outfile" 2>/dev/null || echo 0)

    if [ "$file_size" -gt "$MAX_SIZE_BYTES" ]; then
        # Rotate existing backups (.out.3 gets deleted, .out.2→.out.3, etc.)
        if [ -f "${outfile}.${MAX_ROTATIONS}" ]; then
            rm -f "${outfile}.${MAX_ROTATIONS}"
        fi

        for ((i=MAX_ROTATIONS-1; i>=1; i--)); do
            if [ -f "${outfile}.${i}" ]; then
                mv "${outfile}.${i}" "${outfile}.$((i+1))"
            fi
        done

        # Current .out → .out.1
        mv "$outfile" "${outfile}.1"

        # Create fresh .out with rotation notice
        echo "# Log rotated at $(date -Iseconds) — previous content in ${outfile##*/}.1" > "$outfile"

        ROTATED=$((ROTATED + 1))
        echo "Rotated: $outfile ($(numfmt --to=iec-i --suffix=B "$file_size"))"
    fi
done < <(find "$LOOT_DIR" -name "*.out" -type f -print0 2>/dev/null)

if [ "$ROTATED" -gt 0 ]; then
    echo "Log rotation complete: $ROTATED file(s) rotated."
else
    echo "No .out files exceed 1MB. No rotation needed."
fi
