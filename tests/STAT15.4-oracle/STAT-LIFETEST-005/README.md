# STAT-LIFETEST-005 — LIFETEST — Analysis of Competing-Risks Data

S154 / Chapter 77 / `Analysis of Competing-Risks Data` (PDF pp. 5687–5690).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Getting Started: LIFETEST Procedure |
| [competing_risks.sas](competing_risks.sas) | [output](competing_risks.expected.txt) | [log](competing_risks.oracle.log) | 0 | Cumulative incidence with a censoring code, two failure causes, and two strata. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Restored the official treatment format from physical PDF page 5642.

**competing_risks:** Small explicit synthetic competing-risk input adapted from the official EVENTCODE example. It distinguishes a competing event from a censored observation.
