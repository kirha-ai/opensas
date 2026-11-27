/* expect-rc: 2 */
/* OpenSAS capability guard: full rank does not prove complete cells.
   SAS supports general missing-cell hypotheses; this slice fails visibly. */
data incomplete;
input A $ B $ C $ y;
datalines;
1 1 1 1
1 1 1 3
1 1 2 3
1 1 2 5
1 2 1 5
1 2 1 7
1 2 2 7
1 2 2 9
2 1 1 9
2 1 1 11
2 1 2 11
2 1 2 13
2 2 1 13
2 2 1 15
;
run;
proc glm data=incomplete plots=none;
class A B C;
model y=A B C A*B A*C B*C / ss4;
run;
quit;
