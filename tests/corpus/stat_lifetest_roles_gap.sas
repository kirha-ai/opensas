/* expect-rc: 2
 * STAT-LIFETEST-001: BY, FREQ, WEIGHT and ID each execute, but WEIGHT
 * combined with FREQ has no SAS listing reference; the step must fail
 * visibly (D-009 gap) without printing a partial analysis.
 * Invented data.
 */
data visits;
input site time status arm $ n;
datalines;
1 1 1 A 2
1 2 0 B 1
2 3 1 A 1
2 4 1 B 3
;
run;
proc lifetest data=visits;
time time*status(0);
strata arm;
freq n;
weight n;
by site;
run;
