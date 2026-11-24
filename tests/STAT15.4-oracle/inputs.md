# Fixture inputs

Inputs are part of each SAS program: explicit DATALINES, seeded synthetic generation, and/or an installed public SASHELP member. The input and analysis run together; expected files are captured from the resulting native SAS execution. No private or customer data is used.

SASHELP members listed below are runtime dependencies, not local CSV copies. An OpenSAS replay must supply the same public member (including types, formats, labels, and missing values), or import a separately exported equivalent before comparing results. Native SASHELP data can differ across releases, so the capture runtime version is recorded.

For exact case input, read the referenced program, including data-set options, preprocessing, weights, frequencies, and random seeds. A member name alone does not describe the final analysis rows.

| Public member | Referencing cases | Example |
|---|---:|---|
| SASHELP.BASEBALL | 60 | [STAT-GLMSELECT-001](STAT-GLMSELECT-001/documented_feature.sas) |
| SASHELP.BEI | 17 | [STAT-SASHELP-001](STAT-SASHELP-001/native_contract.sas) |
| SASHELP.BIRTHWGT | 12 | [STAT-CAUSALMED-001](STAT-CAUSALMED-001/documented_feature.sas) |
| SASHELP.BMIMEN | 2 | [STAT-SASHELP-001](STAT-SASHELP-001/native_contract.sas) |
| SASHELP.BMT | 3 | [STAT-LIFETEST-004](STAT-LIFETEST-004/documented_feature.sas) |
| SASHELP.BURROWS | 1 | [STAT-SASHELP-002](STAT-SASHELP-002/native_contract.sas) |
| SASHELP.BWEIGHT | 6 | [STAT-QUANTREG-003](STAT-QUANTREG-003/documented_feature.sas) |
| SASHELP.CARS | 2 | [STAT-BOXPLOT-001](STAT-BOXPLOT-001/documented_feature.sas) |
| SASHELP.CLASS | 36 | [STAT-MCMC-003](STAT-MCMC-003/documented_feature.sas) |
| SASHELP.COMET | 1 | [STAT-SASHELP-003](STAT-SASHELP-003/native_contract.sas) |
| SASHELP.ENSO | 4 | [STAT-GLIMMIX-015](STAT-GLIMMIX-015/documented_feature.sas) |
| SASHELP.FISH | 26 | [STAT-CANDISC-001](STAT-CANDISC-001/documented_feature.sas) |
| SASHELP.GAS | 20 | [STAT-SASHELP-004](STAT-SASHELP-004/native_contract.sas) |
| SASHELP.IRIS | 40 | [STAT-ACECLUS-001](STAT-ACECLUS-001/documented_feature.sas) |
| SASHELP.JUNKMAIL | 2 | [STAT-HPLOGISTIC-006](STAT-HPLOGISTIC-006/documented_feature.sas) |
| SASHELP.LEUTEST | 4 | [STAT-GLMSELECT-009](STAT-GLMSELECT-009/documented_feature.sas) |
| SASHELP.LEUTRAIN | 4 | [STAT-GLMSELECT-009](STAT-GLMSELECT-009/documented_feature.sas) |
| SASHELP.MARGARIN | 14 | [STAT-BCHOICE-001](STAT-BCHOICE-001/documented_feature.sas) |
| SASHELP.MILEAGES | 23 | [STAT-CLUSTER-001](STAT-CLUSTER-001/documented_feature.sas) |
| SASHELP.QUAKES | 2 | [STAT-SASHELP-001](STAT-SASHELP-001/native_contract.sas) |
| SASHELP.SPRINGS | 3 | [STAT-SASHELP-001](STAT-SASHELP-001/native_contract.sas) |
| SASHELP.THICK | 18 | [STAT-SASHELP-001](STAT-SASHELP-001/native_contract.sas) |
| SASHELP.VOTE1980 | 15 | [STAT-GAMPL-001](STAT-GAMPL-001/documented_feature.sas) |

984 programs include inline DATALINES/CARDS; 232 contain explicit random data generation. These counts overlap and are descriptive, not coverage metrics.
