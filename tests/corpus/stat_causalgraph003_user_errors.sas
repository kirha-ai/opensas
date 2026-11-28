/* expect-rc: 1
 * STAT-CAUSALGRAPH-003: invalid MODEL paths are user errors with no listing
 * (SAS 9.4 reference run): a directed self-edge (message text of the run)
 * and an arrow after a covariance path (SAS: ERROR 22-322, expecting ; or
 * a comma). Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph; model "D2" A ==> A, A ==> B; identify A ==> B; run;
proc causalgraph; model "C13" <==> {A B} ==> Y, X ==> Y; identify X ==> Y; run;
