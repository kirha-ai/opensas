/* expect-rc: 1
 * STAT-CAUSALGRAPH-009 (Limitations, p.2329): requests that cannot form a
 * DAG, with no listing. Message texts of SAS 9.4 reference runs
 * (2026-11-28): a self-loop edge; a directed cycle under NOPRINT (one error
 * per cyclic model) and under PSUMMARY (the tables go, the error stays); an
 * outcome missing from a later model wins over a cycle in an earlier one,
 * after its warning. Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph; model 'S' X ==> X, X ==> Y; identify X ==> Y; run;
proc causalgraph noprint; model 'NP' X ==> Y ==> X; identify X ==> Y; run;
proc causalgraph noprint; model 'H1' X ==> Y ==> X; model 'H2' X ==> Z ==> Y ==> Z; identify X ==> Y; run;
proc causalgraph psummary; model 'P' X ==> Y ==> X; identify X ==> Y; run;
proc causalgraph; model 'C1' X ==> Y ==> X; model 'C2' X ==> Z; identify X ==> Y; run;
