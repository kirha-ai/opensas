/* expect-rc: 2
 * STAT-CAUSALGRAPH-001: valid PROC CAUSALGRAPH requests outside the verified
 * scope fail visibly with no listing: the IMAP, COMMON, CYCLES and NOSORT
 * options (PSUMMARY is implemented by STAT-CAUSALGRAPH-002; METHOD=BACKDOOR,
 * METHOD=IV and TESTID by STAT-CAUSALGRAPH-005)
 * (joint effects are implemented by STAT-CAUSALGRAPH-004). Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph imap; model 'M' X ==> Y, Z ==> X Y; run;
proc causalgraph common; model 'M' X ==> Y, Z ==> X Y; identify X ==> Y; run;
proc causalgraph cycles=all; model 'M' X ==> Y, Z ==> X Y; identify X ==> Y; run;
proc causalgraph nosort; model 'M' X ==> Y, Z ==> X Y; identify X ==> Y; run;
