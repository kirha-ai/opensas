/* STAT-HPREG-001: PROC HPREG least-squares fit without a SELECTION
 * statement: performance, data access and model information, observation
 * counts with a missing response, CLASS levels with the GLM
 * parameterization (last level aliased), dimensions, analysis of variance,
 * fit statistics and parameter estimates; NOPRINT prints nothing.
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) output of this program.
 * Invented data.
 * Single edit against the SAS listing: "Number of Threads" is 1 (opensas
 * computes on one thread) where the SAS reference machine printed 2.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data work.inv;
  input b y x1 x2 g $ f w id $;
  datalines;
1 3.1 1 4 A 1 1.0 r01
1 4.0 2 3 B 2 2.0 r02
1 5.2 3 5 A 1 0.5 r03
1 5.9 4 2 B 3 1.5 r04
1 7.4 5 6 A 1 1.0 r05
1 7.8 6 1 B 2 2.5 r06
1 9.6 7 7 A 1 1.0 r07
1 . 8 3 B 1 1.0 r08
2 2.2 1 2 A 1 1.0 r09
2 3.9 2 6 B 1 3.0 r10
2 4.1 3 1 A 2 1.0 r11
2 6.3 4 5 B 1 0.5 r12
2 6.8 5 3 A 1 1.0 r13
2 8.5 6 8 B 2 2.0 r14
2 9.1 7 4 A 1 1.0 r15
;
proc hpreg data=inv;
  model y = x1 x2;
run;
proc hpreg data=inv;
  class g;
  model y = x1 g x2;
run;
proc hpreg data=inv noprint;
  model y = x1;
run;
