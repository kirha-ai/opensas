# STAT-DATASET-004 — Statistical data sets — TYPE=COV Data Sets / TYPE=CSSCP Data Sets / TYPE=DISTANCE Data Sets

## Source

S154 / Special SAS Data Sets / `TYPE=COV Data Sets` (PDF p. 10888); S154 / Special SAS Data Sets / `TYPE=CSSCP Data Sets` (PDF p. 10888); S154 / Special SAS Data Sets / `TYPE=DISTANCE Data Sets` (PDF pp. 10888–10889); S154 / Special SAS Data Sets / `Definitional Formulas` (PDF pp. 10893–10894).

## Scope

Implement TYPE=COV Data Sets; TYPE=CSSCP Data Sets; TYPE=DISTANCE Data Sets including member layouts, reserved variables, matrix/parameter meaning, and read/write contracts.

## Acceptance criteria

Use minimal valid data sets to verify variable types, applicable reserved variables such as _TYPE_/_NAME_, matrix symmetry, and row layouts; preserve semantics through read/write round trips; diagnose missing or conflicting types.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Native correlation/covariance/SSCP rows, reserved variables and data set metadata |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. Covers the named native output in this case; other TYPE= families grouped into the ticket need additional cases. Prints stable variable descriptors and data-set TYPE/NOBS/NVARS, excluding volatile creation timestamps and engine paths. SSCP/CSSCP are requested through the native CORR options; a separate TYPE=SSCP member retains the SSCP rows.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
