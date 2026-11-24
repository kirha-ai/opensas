# STAT-DATASET-002 — Statistical data sets — TYPE=ACE Data Sets / TYPE=BOXPLOT Data Sets / TYPE=CALISFIT Data Sets

S154 / Special SAS Data Sets / `TYPE=ACE Data Sets` (PDF p. 10883); S154 / Special SAS Data Sets / `TYPE=BOXPLOT Data Sets` (PDF p. 10883); S154 / Special SAS Data Sets / `TYPE=CALISFIT Data Sets` (PDF pp. 10883–10884); S154 / Special SAS Data Sets / `Definitional Formulas` (PDF pp. 10893–10894).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [native_contract.sas](native_contract.sas) | [output](native_contract.expected.txt) | [log](native_contract.oracle.log) | 1 | Native TYPE=ACE output and its descriptor |

**native_contract:** Draft case covers the stated observable contract; it is not exhaustive coverage of the ticket. Covers the named native output in this case; other TYPE= families grouped into the ticket need additional cases. Prints stable variable descriptors and data-set TYPE/NOBS/NVARS, excluding volatile creation timestamps and engine paths.
