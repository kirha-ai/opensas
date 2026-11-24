# STAT-DATASET-005 — Statistical data sets — TYPE=EST Data Sets / TYPE=FACTOR Data Sets / TYPE=LINEAR Data Sets

S154 / Special SAS Data Sets / `TYPE=EST Data Sets` (PDF pp. 10889–10890); S154 / Special SAS Data Sets / `TYPE=FACTOR Data Sets` (PDF p. 10890); S154 / Special SAS Data Sets / `TYPE=LINEAR Data Sets` (PDF pp. 10890–10891); S154 / Special SAS Data Sets / `Definitional Formulas` (PDF pp. 10893–10894).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [native_contract.sas](native_contract.sas) | [output](native_contract.expected.txt) | [log](native_contract.oracle.log) | 0 | Native TYPE=EST coefficients, covariance rows and descriptor |

**native_contract:** Draft case covers the stated observable contract; it is not exhaustive coverage of the ticket. Covers the named native output in this case; other TYPE= families grouped into the ticket need additional cases. Prints stable variable descriptors and data-set TYPE/NOBS/NVARS, excluding volatile creation timestamps and engine paths.
