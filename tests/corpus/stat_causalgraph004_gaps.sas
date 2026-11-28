/* expect-rc: 2
 * STAT-CAUSALGRAPH-004: joint effects combined with features outside this
 * ticket fail visibly with no listing. METHOD=IV forbids several treatments
 * or outcomes (p.2303); the SAS message has no reference run, so it stays a
 * D-009 gap (METHOD=BACKDOOR, prescribed variables under METHOD=IV and
 * TESTID are implemented by STAT-CAUSALGRAPH-005).
 * Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph method=iv; model 'M' Z ==> X1 ==> Y, X2 ==> Y, U ==> X1 Y; identify X1 X2 ==> Y; unmeasured U; run;
