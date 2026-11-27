/* STAT-MIXED-013 independent scalar REML deletion contract.
   y=(1,3,5,7), mean=4, SSE=20, residual variance=20/3.
   S154 physical pp.6715-6719. */
ods graphics off;
data influence_sample;
input y;
datalines;
1
3
5
7
;
run;
ods select Influence;
proc mixed data=influence_sample;
model y= / influence;
run;
ods select all;
