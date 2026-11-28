/* expect-rc: 2
 * STAT-SURVEYMEANS-001: an observation with a nonpositive weight is excluded
 * from the analysis; the listing for such input has no reference yet, so the
 * step must fail visibly (D-009 gap) instead of printing unverified counts.
 * Invented data.
 */
data visits;
input y w;
datalines;
11 2
13 0
12 1
16 3
;
proc surveymeans data=visits;
var y;
weight w;
run;
