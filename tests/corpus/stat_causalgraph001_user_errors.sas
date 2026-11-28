/* expect-rc: 1
 * STAT-CAUSALGRAPH-001: documented invalid declarations are user errors with
 * no listing. Message texts of SAS 9.4 reference runs: an unmeasured
 * treatment, LIST with NOLIST, duplicate model labels (labels are not
 * case-sensitive), a directed cycle, a model without an outcome after the
 * IDENTIFY outcome is found in no model (warning first). Documented rules
 * without a reference message: no MODEL statement, a second IDENTIFY or
 * UNMEASURED statement, a variable that is both treatment and outcome, an
 * unmeasured prescribed adjustment variable, MAXLIST=0, an unknown arrow.
 * Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph; model 'D' X ==> Y, U ==> X Y; identify X ==> Y; unmeasured X; run;
proc causalgraph list nolist; model 'D' X ==> Y; identify X ==> Y; run;
proc causalgraph; model 'D' X ==> Y; model 'd' X ==> Y ==> Z; identify X ==> Y; run;
proc causalgraph; model 'E' X ==> Y ==> Z ==> X; identify X ==> Y; run;
proc causalgraph; model 'G' X ==> Y, Z ==> X Y; identify X ==> Q; run;
proc causalgraph; identify X ==> Y; run;
proc causalgraph; model 'D' X ==> Y; identify X ==> Y; identify X ==> Y; run;
proc causalgraph; model 'D' X ==> Y, U ==> X Y; unmeasured U; unmeasured U; run;
proc causalgraph; model 'D' X ==> Y; identify X ==> X; run;
proc causalgraph; model 'D' X ==> Y, U ==> X Y; identify X ==> Y | U; unmeasured U; run;
proc causalgraph maxlist=0; model 'D' X ==> Y; identify X ==> Y; run;
proc causalgraph; model 'D' X =>> Y; run;
