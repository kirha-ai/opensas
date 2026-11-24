# STAT-TPSPLINE-008 — TPSPLINE — ODS Graphics

S154 / Chapter 125 / `ODS Graphics` (PDF pp. 10312–10313).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: TPSPLINE Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Text and ODS trace do not replace visual artifact verification. Routes traditional SAS/GRAPH output to a temporary SVG file in the session, allowing independent replay without server-directory write permissions.
