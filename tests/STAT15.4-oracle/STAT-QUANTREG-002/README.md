# STAT-QUANTREG-002 — QUANTREG — Conditional quantile regression estimation

S154 / Chapter 103 / `Getting Started: QUANTREG Procedure` (PDF pp. 8363–8371); S154 / Chapter 103 / `Overview: QUANTREG Procedure` (PDF pp. 8358–8363).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_default.sas](documented_default.sas) | [output](documented_default.expected.txt) | [log](documented_default.oracle.log) | 0 | Example 103.1: Comparison of Algorithms |

**documented_default:** Draft replay adapted from the cited code. No inference about unexercised options is made. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. QUANTREG random seeds are explicitly set on MODEL, as required by the native statement syntax.
