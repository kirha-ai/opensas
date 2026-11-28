/* expect-rc: 2
 * STAT-CAUSALGRAPH-001: valid PROC CAUSALGRAPH requests outside the verified
 * scope fail visibly with no listing: METHOD=BACKDOOR and METHOD=IV, the
 * TESTID statement, the IMAP, COMMON, CYCLES, PSUMMARY and NOSORT options,
 * bidirected edges, several MODEL statements, a disconnected model (the
 * ConnectedComponents table) and a joint effect. Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph method=backdoor; model 'M' X ==> Y, Z ==> X Y; identify X ==> Y; run;
proc causalgraph method=iv; model 'M' Z ==> X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; run;
proc causalgraph; model 'M' X ==> Y, Z ==> X Y; identify X ==> Y; testid Z; run;
proc causalgraph imap; model 'M' X ==> Y, Z ==> X Y; run;
proc causalgraph common; model 'M' X ==> Y, Z ==> X Y; identify X ==> Y; run;
proc causalgraph cycles=all; model 'M' X ==> Y, Z ==> X Y; identify X ==> Y; run;
proc causalgraph psummary; model 'M' X ==> Y, Z ==> X Y; identify X ==> Y; run;
proc causalgraph nosort; model 'M' X ==> Y, Z ==> X Y; identify X ==> Y; run;
proc causalgraph; model 'M' X ==> Y <==> X; identify X ==> Y; run;
proc causalgraph; model 'M' X ==> Y; model 'N' X ==> Y, Z ==> X Y; identify X ==> Y; run;
proc causalgraph; model 'F' X ==> Y, A ==> B; identify X ==> Y; run;
proc causalgraph; model 'J' X1 X2 ==> Y, Z ==> X1 Y; identify X1 X2 ==> Y; run;
