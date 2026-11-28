/* expect-rc: 2
 * STAT-NLMIXED-001: PROC NLMIXED parses and validates the step (PROC
 * options, PARMS, BOUNDS, programming statements, MODEL, nested RANDOM
 * statements, ID, BY), but marginal likelihood estimation (adaptive Gaussian
 * quadrature with dual quasi-Newton optimization) belongs to STAT-NLMIXED-002.
 * Each step must fail visibly (D-009 gap) and print no table, never a
 * plausible-looking listing; so must later-ticket options and statements.
 * Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data plants;
input grp site plot y;
datalines;
1 1 1 10.2
1 1 1 10.9
1 1 2 9.4
1 1 2 9.9
1 2 1 12.1
1 2 1 11.6
1 2 2 11.0
1 2 2 11.8
2 1 1 10.5
2 1 1 10.1
2 1 2 9.0
2 1 2 9.7
2 2 1 12.4
2 2 1 12.0
2 2 2 11.2
2 2 2 11.5
;
run;
proc nlmixed data=plants;
parms intercept=10 s2=1;
bounds vs >= 0, vp >= 0;
mean = intercept + us + up;
model y ~ normal(mean, s2);
random us ~ normal(0, vs) subject=site;
random up ~ normal(0, vp) subject=plot(site);
id mean;
run;
proc nlmixed data=plants alpha=0.1;
by grp;
mean = intercept + us;
model y ~ normal(mean, s2);
random us ~ normal(0, vs) subject=site;
run;
proc nlmixed data=plants qpoints=3;
mean = intercept + us;
model y ~ normal(mean, s2);
random us ~ normal(0, vs) subject=site;
run;
proc nlmixed data=plants;
mean = intercept + us;
model y ~ normal(mean, s2);
random us ~ normal(0, vs) subject=site out=eb;
run;
proc nlmixed data=plants;
mean = intercept + us;
model y ~ normal(mean, s2);
random us ~ normal(0, vs) subject=site;
predict mean out=pred;
run;
proc nlmixed data=plants;
mean = intercept;
model y ~ normal(mean, s2);
run;
