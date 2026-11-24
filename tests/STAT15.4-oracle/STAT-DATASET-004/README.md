# STAT-DATASET-004 — Statistical data sets — TYPE=COV Data Sets / TYPE=CSSCP Data Sets / TYPE=DISTANCE Data Sets

S154 / Special SAS Data Sets / `TYPE=COV Data Sets` (PDF p. 10888); S154 / Special SAS Data Sets / `TYPE=CSSCP Data Sets` (PDF p. 10888); S154 / Special SAS Data Sets / `TYPE=DISTANCE Data Sets` (PDF pp. 10888–10889); S154 / Special SAS Data Sets / `Definitional Formulas` (PDF pp. 10893–10894).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [native_contract.sas](native_contract.sas) | [output](native_contract.expected.txt) | [log](native_contract.oracle.log) | 0 | Native correlation/covariance/SSCP rows, reserved variables and data set metadata |

**native_contract:** Draft case covers the stated observable contract; it is not exhaustive coverage of the ticket. Covers the named native output in this case; other TYPE= families grouped into the ticket need additional cases. Prints stable variable descriptors and data-set TYPE/NOBS/NVARS, excluding volatile creation timestamps and engine paths. SSCP/CSSCP are requested through the native CORR options; a separate TYPE=SSCP member retains the SSCP rows.
