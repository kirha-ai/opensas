/* STAT-CAUSALGRAPH-003: MODEL statement warnings (pp.2305-2306). Message
 * texts and their order are those of a SAS 9.4 reference run of these
 * invented graphs: a repeated directed edge (also when respelled with a left
 * arrow), repeated bidirected edges (a covariance path names the later
 * variable first), a one-variable covariance path, and a variance
 * specification X <==> X; a disconnected model (repeated bidirected edges
 * and variance specifications in the D3 order of the run: variance first),
 * two disconnected models, a prescribed adjustment variable missing from
 * one model.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
proc causalgraph; model "D1" A ==> B, A ==> B, B <== A, A ==> C ==> B; identify A ==> B; run;
proc causalgraph; model "C4" X1 ==> X2 ==> X3 <== X4 <==> X5, X5 <==> X4, <==> {X4 X5}, X4 <-> X5, X5 ==> X3; identify X2 ==> X3; run;
proc causalgraph; model "C9" X ==> Y, <==> {X}; identify X ==> Y; run;
proc causalgraph; model "C10" X ==> Y, X <==> X; identify X ==> Y; run;
proc causalgraph; model "D3" X ==> Y, A <==> B, B <==> C, A <==> C, <==> {A B C}, {A B} <==> {B C}, <==> {Y Y X}; identify X ==> Y; run;
proc causalgraph; model "E1" X ==> Y, B ==> A, C ==> A; identify X ==> Y; run;
proc causalgraph; model "P" X ==> Y, A ==> B; model "Q" X ==> Y, C ==> D; identify X ==> Y; run;
proc causalgraph; model "P2" X ==> Y, Z ==> X Y; model "Q" X ==> Y, W ==> X; identify X ==> Y | Z; run;
