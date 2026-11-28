/* expect-rc: 2
 * STAT-HP-001: PERFORMANCE requests opensas cannot honour truthfully must
 * fail visibly (D-009 gap) before any listing text, in every HP procedure
 * that shares the single-machine contract: a thread count other than 1
 * (opensas computes on one thread), DETAILS task timing and BPC=
 * (STAT-HP-002), and the distributed execution options of SAS
 * High-Performance Analytics (NODES=, HOST=, ...), which are an execution
 * mode opensas does not have. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data s;
 input x y g $;
 datalines;
1 2 A
2 3 B
3 5 A
4 4 B
5 7 A
6 8 B
;
run;
proc hpreg data=s; model y = x; performance nthreads=1 details; run;
proc hpreg data=s; model y = x; performance nthreads=4; run;
proc hpreg data=s; model y = x; performance nodes=4; run;
proc hpreg data=s; model y = x; performance host="grid.example.com"; run;
proc hpreg data=s; model y = x; performance bpc=1; run;
proc hpgenselect data=s; model y = x / dist=poisson; performance details; run;
proc hplogistic data=s; model g = x; performance nthreads=2; run;
proc hpprincomp data=s; var x y; performance gridmode=asym; run;
proc hpmixed data=s; class g; model y = x; random g; performance nthreads=8; run;
