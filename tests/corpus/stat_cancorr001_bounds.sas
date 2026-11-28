/* STAT-CANCORR-001: boundary inputs, invented data. A variable in both the
 * VAR and WITH statements and a WITH variable that is an exact linear
 * function of a VAR variable give a canonical correlation of one (Infty
 * eigenvalue, missing proportion, Hotelling-Lawley and Roy shown missing);
 * two correlations of one; a zero canonical correlation; a linearly
 * dependent or constant variable (rank NOTE, tests use the rank); both sets
 * deficient (fewer canonical variables); no more observations than
 * variables (zero denominator df, no multivariate table). Coefficient pages
 * are shown only where SAS 9.4's signs are reproduced (see
 * src/stat/cancorr.zig); the others use SHORT. Expected output is the SAS
 * 9.4 (SAS/STAT 15.4) listing of this program.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data T;
input a b c d e;
s = a + b;
k = 2*a + 1;
t = c + d;
m = 3*b;
z = 5;
datalines;
1 2 5 3 4
2 1 3 4 2
3 4 4 1 6
4 3 1 5 1
5 5 2 2 5
6 2 6 6 3
7 6 2 4 7
8 4 5 2 2
;
proc cancorr data=T short; var a b c; with c d; run;
proc cancorr data=T; var a; with k; run;
proc cancorr data=T short; var a b c; with k d e; run;
proc cancorr data=T short; var a b; with k m; run;
data Z; input a b; datalines;
1 1
2 -1
3 -1
4 1
;
proc cancorr data=Z; var a; with b; run;
proc cancorr data=T short; var a b s; with c d; run;
proc cancorr data=T short vname='Alpha' wname='Beta'; var c d; with a b s; run;
proc cancorr data=T short; var a b s; with c d t; run;
proc cancorr data=T short; var a b z; with c d; run;
data F4; set T; if _n_ <= 4; run;
proc cancorr data=F4 short; var a b; with c d; run;
data F2; set T; if _n_ <= 2; run;
proc cancorr data=F2 short; var a; with c; run;
