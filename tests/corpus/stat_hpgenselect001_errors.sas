/* expect-rc: 1
 * STAT-HPGENSELECT-001: invalid PROC HPGENSELECT declarations are user
 * errors (rc 1) and print nothing: an unknown option, ALPHA= outside (0,1),
 * a missing MODEL statement, CLASS after MODEL, a character response, a
 * character regressor not named in CLASS, a character FREQ or WEIGHT
 * variable, an unknown ID variable, an unknown DISTRIBUTION= keyword, an
 * unknown MODEL option, and a BY variable that is not sorted. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data cnt;
input g x y f w c $;
datalines;
1 0.5 2 1 1.0 a
1 1.2 3 2 0.5 b
1 2.0 5 1 2.0 a
2 0.3 0 3 1.0 b
2 1.1 1 1 1.5 a
2 1.9 4 2 1.0 b
3 0.4 1 1 0.8 a
3 1.4 2 1 1.2 b
3 2.2 6 2 1.0 a
;
run;
proc hpgenselect data=cnt bogus; model y = x / dist=poisson; run;
proc hpgenselect data=cnt alpha=1.5; model y = x / dist=poisson; run;
proc hpgenselect data=cnt; class g; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; class g; run;
proc hpgenselect data=cnt; model c = x / dist=poisson; run;
proc hpgenselect data=cnt; model y = c / dist=poisson; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; freq c; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; weight c; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; id nosuch; run;
proc hpgenselect data=cnt; model y = x / dist=wobbly; run;
proc hpgenselect data=cnt; model y = x / dist=poisson wobble; run;
proc hpgenselect data=cnt; by c; model y = x / dist=poisson; run;
