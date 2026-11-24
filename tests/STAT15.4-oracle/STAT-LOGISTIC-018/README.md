# STAT-LOGISTIC-018 — LOGISTIC — CODE / SCORE / Linear Predictor, Predicted Probability, and Confidence Limits

S154 / Chapter 79 / `CODE Statement` (PDF p. 5855); S154 / Chapter 79 / `SCORE Statement` (PDF pp. 5898–5900); S154 / Chapter 79 / `Linear Predictor, Predicted Probability, and Confidence Limits` (PDF pp. 5925–5926).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Example 79.16: Scoring Data Sets; explicit statements: SCORE |
| [statement_code.sas](statement_code.sas) | [output](statement_code.expected.txt) | [log](statement_code.oracle.log) | 0 | Generate DATA step scoring code, execute it against the input rows, and print the scored data. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: SCORE. Remaining statement variants: CODE.

**statement_code:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.
