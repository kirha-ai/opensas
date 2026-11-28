/* STAT-CAUSALGRAPH-003: MODEL statement warnings (pp.2305-2306). Message
 * texts and their order are those of a SAS 9.4 reference run of these
 * invented graphs: a repeated directed edge (also when respelled with a left
 * arrow), repeated bidirected edges (a covariance path names the later
 * variable first), a one-variable covariance path, and a variance
 * specification X <==> X.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
proc causalgraph; model "D1" A ==> B, A ==> B, B <== A, A ==> C ==> B; identify A ==> B; run;
proc causalgraph; model "C4" X1 ==> X2 ==> X3 <== X4 <==> X5, X5 <==> X4, <==> {X4 X5}, X4 <-> X5, X5 ==> X3; identify X2 ==> X3; run;
proc causalgraph; model "C9" X ==> Y, <==> {X}; identify X ==> Y; run;
proc causalgraph; model "C10" X ==> Y, X <==> X; identify X ==> Y; run;
