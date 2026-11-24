# STAT-DATASET-001 — Statistical data set types, matrices, and reserved metadata contracts

S154 / Special SAS Data Sets / `Introduction to Special SAS Data Sets` (PDF pp. 10880–10883).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [native_contract.sas](native_contract.sas) | [output](native_contract.expected.txt) | [log](native_contract.oracle.log) | 0 | Native factor/correlation structure rows and descriptor |

**native_contract:** Draft case covers the stated observable contract; it is not exhaustive coverage of the ticket. Covers the named native output in this case; other TYPE= families grouped into the ticket need additional cases. Prints stable variable descriptors and data-set TYPE/NOBS/NVARS, excluding volatile creation timestamps and engine paths.
