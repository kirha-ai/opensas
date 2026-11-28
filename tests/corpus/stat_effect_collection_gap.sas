/* expect-rc: 2
 * STAT-COMMON-021: EFFECT forms parsed by the shared module but not adopted
 * by PROC GLMSELECT yet (LAG effects, collection DETAILS, CLASS constituents)
 * must fail visibly (D-009 gap) without printing a partial analysis.
 * Invented data.
 */
options nosyntaxcheck linesize=160;
data lagd;
 input subject $ period treatment $ x y;
 datalines;
S1 1 A 1 3
S2 1 B 2 4
S1 2 B 3 6
S2 2 A 4 3
S1 3 A 5 8
S2 3 B 6 2
;
run;
proc glmselect data=lagd;
 class treatment;
 effect L = lag(treatment / within=subject period=period);
 model y = L / selection=none;
run;
proc glmselect data=lagd;
 effect c = collection(x period / details);
 model y = c / selection=none;
run;
proc glmselect data=lagd;
 class treatment;
 effect c = collection(x treatment);
 model y = c / selection=none;
run;
