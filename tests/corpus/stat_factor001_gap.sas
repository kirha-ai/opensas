/* expect-rc: 2
 * STAT-FACTOR-001: valid PROC FACTOR requests outside the implemented
 * METHOD=PRINCIPAL PRIORS=ONE unrotated analysis (here ROTATE=VARIMAX, owned
 * by a later FACTOR ticket) must fail visibly (D-009 gap) and print nothing
 * for the step. Invented data.
 */
data scores;
input a b c;
datalines;
1 2 3
2 1 5
3 4 4
4 3 8
5 6 7
6 5 9
;
proc factor data=scores rotate=varimax;
run;
