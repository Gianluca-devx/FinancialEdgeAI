#!/bin/sh
# Phase 2g (Specs/phase-2g-table-reader.md): builds the Mac driver of the statement table reader from the app's own source
# files (FinancialEdgeAI/Services, the same files the app compiles) and runs it from the repository root.
#
#   Scripts/table_reader.sh --condition A|C [--out RealSet/pdf] [--reports ~/Downloads/Reports]
#
# Then score with the PDF pilot's scorer, unchanged:  python3 Scripts/pdf_pilot.py score --pred RealSet/pdf/pred.reader.A.pdfkit.json
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SERVICES="$ROOT/FinancialEdgeAI/Services"
BIN="${TMPDIR:-/tmp}/financialedgeai-table-reader"
swiftc -O -swift-version 5 -o "$BIN" "$SERVICES/StatementTable.swift" "$SERVICES/StatementTableReader.swift" \
    "$SERVICES/PDFStatementLines.swift" "$ROOT/Scripts/table_reader/main.swift"
cd "$ROOT"
exec "$BIN" "$@"
