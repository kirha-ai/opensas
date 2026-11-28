/* expect-rc: 1
 * STAT-COMMON-021: EFFECT user errors in PROC GLMSELECT: an EFFECT
 * statement after MODEL (p.424: all EFFECT statements must precede the MODEL
 * statement), an effect name that is a data set variable, an option other
 * than DETAILS in a collection effect. Each step stops with an ERROR and
 * prints nothing. Invented data.
 */
options nosyntaxcheck linesize=160;
data small;
 input x z y;
 datalines;
1 1 4
2 3 6
3 2 7
4 5 9
5 3 13
6 4 12
;
run;
proc glmselect data=small;
 model y = x / selection=none;
 effect both = collection(x z);
run;
proc glmselect data=small;
 effect x = collection(x z);
 model y = x / selection=none;
run;
proc glmselect data=small;
 effect both = collection(x z / nlag=2);
 model y = both / selection=none;
run;
