/* expect-rc: 2
 * STAT-CAUSALGRAPH-005: the minimality check of a TESTID set with more
 * than 20 variables (exhaustive subset search) fails visibly (D-009).
 * Invented graph.
 */
options nosyntaxcheck;
proc causalgraph; model 'G' X ==> Y, {A1-A21} ==> Y; identify X ==> Y; testid A1-A21; run;
