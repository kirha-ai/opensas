/* STAT-MIXED-001: the real PROC dispatcher reaches declarations and input,
   but must not fabricate an unimplemented MIVQUE0 analysis. expect-rc: 2 */
data sample;
input g y x w;
datalines;
1 2 1 0.5
1 4 2 2
2 6 3 1
;
run;
proc mixed data=sample method=mivque0;
by g;
weight w;
id;
model y=x;
run;
