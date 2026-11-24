# STAT-DATASET-008 — Statistical data sets — TYPE=UCOV Data Sets / TYPE=WEIGHT Data Sets

S154 / Special SAS Data Sets / `TYPE=UCOV Data Sets` (PDF p. 10893); S154 / Special SAS Data Sets / `TYPE=WEIGHT Data Sets` (PDF p. 10893); S154 / Special SAS Data Sets / `Definitional Formulas` (PDF pp. 10893–10894).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [native_contract.sas](native_contract.sas) | [output](native_contract.expected.txt) | [log](native_contract.oracle.log) | 0 | Native factor/correlation structure rows and descriptor |

**native_contract:** Draft case covers the stated observable contract; it is not exhaustive coverage of the ticket. Covers the named native output in this case; other TYPE= families grouped into the ticket need additional cases. Prints stable variable descriptors and data-set TYPE/NOBS/NVARS, excluding volatile creation timestamps and engine paths.
