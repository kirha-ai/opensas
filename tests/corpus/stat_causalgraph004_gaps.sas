/* expect-rc: 2
 * STAT-CAUSALGRAPH-004: joint effects combined with features outside this
 * ticket fail visibly with no listing. METHOD=IV forbids several treatments
 * or outcomes and ignores prescribed variables (p.2303), METHOD=BACKDOOR and
 * TESTID are owned by STAT-CAUSALGRAPH-005; until then each is a D-009 gap.
 * Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph method=iv; model 'M' Z ==> X1 ==> Y, X2 ==> Y, U ==> X1 Y; identify X1 X2 ==> Y; unmeasured U; run;
proc causalgraph method=iv; model 'M' Z ==> X ==> Y, U ==> X Y, C ==> Y; identify X ==> Y | C; unmeasured U; run;
proc causalgraph method=backdoor; model 'M' X1 X2 ==> Y, Z ==> X1 Y; identify X1 X2 ==> Y; run;
proc causalgraph; model 'M' X1 X2 ==> Y, Z ==> X1 Y; identify X1 X2 ==> Y; testid X2; run;
