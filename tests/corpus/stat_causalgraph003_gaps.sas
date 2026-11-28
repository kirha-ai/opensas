/* expect-rc: 2
 * STAT-CAUSALGRAPH-003: the UNMEASURED rule for TESTID variables (p.2309)
 * needs the TESTID statement, owned by STAT-CAUSALGRAPH-005: it fails
 * visibly with no listing. Invented graph.
 */
options nosyntaxcheck;
proc causalgraph; model "T" Z ==> X ==> Y, U ==> X Y; identify X ==> Y; testid U; unmeasured U; run;
