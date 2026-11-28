/* STAT-RSREG-001: MODEL display options (S154 pp.8875-8876). NOANOVA keeps
 * the coding table and the canonical analysis (saddle point); one factor
 * prints a zero-DF Crossproduct row; NOOPTIMAL drops the canonical page;
 * MODEL NOPRINT and PROC NOPRINT print nothing. Invented data; every token
 * was checked against a SAS 9.4 reference run (NOPRINT per p.8858/p.8876).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data s; input y x1 x2 @@; datalines;
5 -1 -1  9 -1 1  8 1 -1  2 1 1  6 0 0  7 0 0  4 0 1  3 1 0  9 -1 0  6 0 -1
;
title 'P3 saddle';
proc rsreg data=s; model y = x1 x2 / noanova; run;
title 'P4 one factor';
proc rsreg data=s; model y = x1; run;
title 'P5 nooptimal';
proc rsreg data=s; model y = x1 / noopt; run;
title 'P6 noprint';
proc rsreg data=s; model y = x1 x2 / noprint; run;
proc rsreg data=s noprint; model y = x1 x2; run;
