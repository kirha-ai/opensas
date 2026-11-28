/* STAT-MODECLUS-001: PROC MODECLUS Getting Started (published sample data,
 * S154 Chapter 85 pp.6813-6816): METHOD=1 with an R= list, the default
 * Cluster Statistics and Cluster Summary listing and the OUT= data set
 * (row count and the leading rows of a SAS 15.4 reference run, checked in a
 * DATA step because the PROC PRINT decimal alignment is a known Base
 * blocker). The original's PROC SGPLOT
 * steps are omitted (PROC SGPLOT is not implemented).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data example;
input x y @@;
datalines;
18 18 20 22 21 20 12 23 17 12 23 25 25 20 16 27
20 13 28 22 80 20 75 19 77 23 81 26 55 21 64 24
72 26 70 35 75 30 78 42 18 52 27 57 41 61 48 64
59 72 69 72 80 80 31 53 51 69 72 81
;
proc modeclus data=example method=1 r=10 15 35 out=out;
run;
data _null_;
file print;
set out end=last;
retain ok 1;
/* SAS 15.4 reference rows 1-5: DENSITY .000954930 .000954930 .001061033
   .000530516 .000424413, CLUSTER 1, _R_ 10, _METHOD_ 1, _OBS_ 1-5. */
if _n_ <= 5 then do;
  if abs(density - choosen(_n_, .000954930, .000954930, .001061033, .000530516, .000424413)) >= 5e-10
     or cluster ne 1 or _r_ ne 10 or _method_ ne 1 or _obs_ ne _n_ then ok = 0;
end;
if last then put 'rows=' _n_ 'ok=' ok;
run;
