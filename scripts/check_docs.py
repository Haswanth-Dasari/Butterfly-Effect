#!/usr/bin/env python3
"""Fails if any `path` mentioned in docs/concept_coverage_matrix.md does not exist."""
import re, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
text = (root / "docs/concept_coverage_matrix.md").read_text(encoding="utf-8")
bad = []
for p in sorted(set(re.findall(r"`([^`\s]+\.[a-z0-9]+|[^`\s]+/)`", text))):
    if p.startswith("db/") or p.startswith("experiments/") or p.startswith("docs/") or p.startswith("backend/") or p.startswith("frontend/"):
        if "exp8_partitioning.csv" in p: continue          # produced when the experiment is run
        if not (root / p).exists(): bad.append(p)
print("missing:", bad or "none"); sys.exit(1 if bad else 0)
