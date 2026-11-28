/* expect-rc: 2
 * STAT-QUANTREG-001: ALGORITHM=INTERIOR with ITPRINT is valid SAS whose
 * iteration history is owned by STAT-QUANTREG-004; the step must fail
 * visibly (D-009 gap) without printing a partial listing. Invented data.
 */
data q;
input x y;
datalines;
1 1.2
2 1.9
3 3.4
4 3.8
5 5.3
;
run;
proc quantreg algorithm=interior(tolerance=1e-6) ci=none data=q;
model y = x / itprint nosummary;
run;
