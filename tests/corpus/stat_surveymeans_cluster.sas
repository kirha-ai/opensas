/* STAT-SURVEYMEANS-001: PROC SURVEYMEANS with STRATA, CLUSTER, CLASS and
 * RATE=. Invented data. Expected values by hand: units are the 4 clusters,
 * df = 4 - 2 = 2, ybar = 13.5; cluster totals of (y - ybar)/6 are
 * -0.5, 0.25 | -0.25, 0.5, so each stratum gives 2 * 0.28125 and
 * V = (1 - 0.1) * 1.125; t(0.975, 2) = 4.30265273.
 * So y: stderr 1.006231, limits 9.17053921 and 17.8294608.
 * part=1 has proportion 0.5 with cluster totals of (I - 0.5)/6 equal to
 * 0, 1/12 | -1/12, 0: V = 0.9 * 2 * (2 * 1/288) = 0.0125, stderr 0.111803,
 * limits 0.5 -+ 0.481051.
 */
options nodate nonumber nocenter linesize=160;
data visits;
input region site y part;
datalines;
1 1 11 1
1 1 13 2
1 2 15 1
2 1 12 2
2 2 14 1
2 2 16 2
;
proc surveymeans data=visits rate=0.1;
strata region;
cluster site;
class part;
var y part;
run;
