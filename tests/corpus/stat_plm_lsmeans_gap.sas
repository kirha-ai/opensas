/* STAT-PLM-002: expect-rc: 2
 * The LSMEANS / LSMESTIMATE / SLICE steps of the PLM Getting Started example
 * are not implemented: the step must fail loudly (D-009 gap) and print
 * nothing, even though SHOW and TEST in the same step are supported.
 * Invented data. */
data cells;
input g $ h $ y @@;
datalines;
A U 4 A U 6 A V 7 A V 9 B U 13 B U 12 B V 15 B V 18
;
proc glm data=cells noprint;
class g h;
model y = g h;
store fit;
run;
proc plm restore=fit;
show fit parms;
lsmestimate g -1 1 / uppertailed ftest;
run;
