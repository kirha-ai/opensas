/* expect-rc: 2
 * STAT-CAUSALGRAPH-002: PSUMMARY with a disconnected model has no reference
 * layout (ConnectedComponents kept or not): it fails visibly with no
 * listing. Invented graph.
 */
options nosyntaxcheck;
proc causalgraph psummary disconnected; model 'D' X ==> Y, Z ==> X, A ==> B; identify X ==> Y; run;
