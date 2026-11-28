/* STAT-HP-001: shared single-machine contract of the high-performance
 * procedures (SAS/STAT 15.4 Chapter 21, pp.555-558). The same invented data
 * reached through three supported access paths (one-level DATA=, two-level
 * WORK DATA=, and the _LAST_ default) with PERFORMANCE NTHREADS=1 / THREADS=1
 * or none must give the same listing. Expected words: the SAS 9.4 listing of
 * tests/STAT15.4-oracle/STAT-HP-001 (PROC HPREG ... PERFORMANCE NTHREADS=1
 * DETAILS) up to the Procedure Task Timing table, which DETAILS adds and which
 * is a loud gap (STAT-HP-002, see stat_hp001_gaps.sas). Number of Threads 1
 * is both the SAS value for NTHREADS=1 and the truthful opensas value.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data sample;
 input x z y group $ weight freq;
 datalines;
1 1 4 A 1 1
2 1 6 A 2 1
3 2 7 A 1 2
4 1 9 A 1 1
5 3 13 A 2 1
6 2 12 A 1 1
7 4 17 B 1 1
8 3 19 B 2 2
9 5 20 B 1 1
10 3 23 B 1 1
11 5 25 B 2 1
12 4 24 B 1 1
;
run;
proc hpreg data=sample; class group; model y=x z group; performance nthreads=1; run;
proc hpreg data=work.sample; class group; model y=x z group; performance threads=1; run;
proc hpreg; class group; model y=x z group; run;
