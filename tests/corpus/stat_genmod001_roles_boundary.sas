/* STAT-GENMOD-001: PROC GENMOD declarations and roles validate, then the step
   stops at a loud execution boundary. expect-rc: 2
   The step is valid SAS (SAS/STAT 15.4 ch.51): BY, CLASS, MODEL with DIST=/LINK=,
   FREQ and WEIGHT. Estimation belongs to STAT-GENMOD-002, so opensas must
   report an unimplemented-feature ERROR (exit 2) and print no table at all.
   Invented data. */
data t;
input g c $ x y f w;
datalines;
1 a 0 5 1 1
1 b 1 7 2 1
1 a 2 9 1 2
2 b 0 4 1 1
2 a 1 6 1 1
2 b 2 9 3 1
;
proc genmod data=t namelen=30 order=data;
by g;
class c;
model y = x c / dist = normal link = log;
freq f;
weight w;
run;
