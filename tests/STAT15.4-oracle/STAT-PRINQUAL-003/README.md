# STAT-PRINQUAL-003 — PRINQUAL — TRANSFORM / The Three Methods of Variable Transformation / Understanding How PROC PRINQUAL Works

S154 / Chapter 99 / `TRANSFORM Statement` (PDF pp. 8049–8057); S154 / Chapter 99 / `The Three Methods of Variable Transformation` (PDF pp. 8057–8058); S154 / Chapter 99 / `Understanding How PROC PRINQUAL Works` (PDF pp. 8058–8062).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 1 | Example 99.1: Multidimensional Preference Analysis of Automobile Data; explicit statements: TRANSFORM |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TRANSFORM. Remaining statement variants: . Reconstructed Make/Model field padding so the 25 one-digit official ratings start in column 25.
