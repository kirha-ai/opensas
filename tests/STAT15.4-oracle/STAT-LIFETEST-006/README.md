# STAT-LIFETEST-006 — LIFETEST — Restricted Mean Analysis

S154 / Chapter 77 / `Restricted Mean Analysis` (PDF pp. 5690–5692).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: LIFETEST Procedure |
| [restricted_means.sas](restricted_means.sas) | [output](restricted_means.expected.txt) | [log](restricted_means.oracle.log) | 0 | Restricted mean survival time and restricted mean time lost at an explicit tau of 6. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Restored the official treatment format from physical PDF page 5642.

**restricted_means:** Small synthetic input with explicit truncation time. Inspect RMST/RMTL estimates and group comparisons, not just ordinary survival tables.
