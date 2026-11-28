/* expect-rc: 2
 * STAT-RSREG-001: PLOTS= with ODS GRAPHICS ON requests graphs owned by
 * STAT-RSREG-008, a visible gap; with ODS GRAPHICS OFF the same option
 * draws nothing (S154 p.8858), so the tables of the first step print.
 * Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data s; input y x1 x2 @@; datalines;
5 -1 -1  9 -1 1  8 1 -1  2 1 1  6 0 0  7 0 0  4 0 1  3 1 0  9 -1 0  6 0 -1
;
ods graphics off;
proc rsreg data=s plots=surface; model y = x1 x2 / noanova; run;
ods graphics on;
proc rsreg data=s plots(unpack)=surface(3d); model y = x1 x2; run;
ods graphics off;
