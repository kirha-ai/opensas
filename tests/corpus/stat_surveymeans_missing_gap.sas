/* expect-rc: 2
 * STAT-SURVEYMEANS-001: TOTAL= together with a missing analysis value. The
 * per-variable design of the nonmissing observations may have fewer
 * sampling units than the whole sample, and which count the finite
 * population correction uses has no reference yet, so the step must fail
 * visibly (D-009 gap). Invented data.
 */
data visits;
input y h;
datalines;
11 1
13 1
. 1
16 2
15 2
;
proc surveymeans data=visits total=20;
var y;
strata h;
run;
