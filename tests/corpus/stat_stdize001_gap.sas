/* expect-rc: 2
 * STAT-STDIZE-001: a valid PROC STDIZE request outside the implemented
 * closed-form measures (here the biweight METHOD=ABW(4), owned by
 * STAT-STDIZE-003) must fail visibly (D-009 gap) and create or print nothing
 * for the step. Invented data.
 */
data scores;
input total @@;
datalines;
135 125 223 224 133 253 144 193
;
proc stdize data=scores out=s method=abw(4) pstat;
var total;
run;
