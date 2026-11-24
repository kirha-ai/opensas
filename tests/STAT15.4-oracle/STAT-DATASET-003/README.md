# STAT-DATASET-003 — Statistical data sets — TYPE=CALISMDL Data Sets / TYPE=CHARTSUM Data Sets / TYPE=CORR Data Sets

S154 / Special SAS Data Sets / `TYPE=CALISMDL Data Sets` (PDF p. 10884); S154 / Special SAS Data Sets / `TYPE=CHARTSUM Data Sets` (PDF p. 10884); S154 / Special SAS Data Sets / `TYPE=CORR Data Sets` (PDF pp. 10884–10888); S154 / Special SAS Data Sets / `Definitional Formulas` (PDF pp. 10893–10894).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [native_contract.sas](native_contract.sas) | [output](native_contract.expected.txt) | [log](native_contract.oracle.log) | 0 | Native correlation/covariance/SSCP rows, reserved variables and data set metadata |

**native_contract:** Draft case covers the stated observable contract; it is not exhaustive coverage of the ticket. Covers the named native output in this case; other TYPE= families grouped into the ticket need additional cases. Prints stable variable descriptors and data-set TYPE/NOBS/NVARS, excluding volatile creation timestamps and engine paths. SSCP/CSSCP are requested through the native CORR options; a separate TYPE=SSCP member retains the SSCP rows.
