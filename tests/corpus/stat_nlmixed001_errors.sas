/* expect-rc: 1
 * STAT-NLMIXED-001: invalid PROC NLMIXED declarations are user errors
 * (rc 1): an unknown PROC option, ALPHA= outside (0,1), a missing MODEL
 * statement, a second MODEL statement, an unknown or character dependent
 * variable, a distribution with the wrong number of arguments, a
 * programming statement after MODEL, a RANDOM statement without SUBJECT=,
 * a non-normal random-effects distribution, an unknown SUBJECT= variable, a
 * data set variable used as a PARMS name, and BY input that is not sorted.
 * Nothing is printed. Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data obs;
input s x y t $;
datalines;
2 1 3.2 u
1 2 4.1 u
2 3 5.0 u
3 4 6.3 u
;
run;
proc nlmixed data=obs bogus;
eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;
run;
proc nlmixed data=obs alpha=1.5;
eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;
run;
proc nlmixed data=obs;
eta = b0 + u; random u ~ normal(0, g) subject=s;
run;
proc nlmixed data=obs;
eta = b0 + u; model y ~ normal(eta, s2); model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;
run;
proc nlmixed data=obs;
eta = b0 + u; model nosuch ~ normal(eta, s2); random u ~ normal(0, g) subject=s;
run;
proc nlmixed data=obs;
eta = b0 + u; model t ~ normal(eta, s2); random u ~ normal(0, g) subject=s;
run;
proc nlmixed data=obs;
eta = b0 + u; model y ~ normal(eta); random u ~ normal(0, g) subject=s;
run;
proc nlmixed data=obs;
model y ~ normal(eta, s2); eta = b0 + u; random u ~ normal(0, g) subject=s;
run;
proc nlmixed data=obs;
eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g);
run;
proc nlmixed data=obs;
eta = b0 + u; model y ~ normal(eta, s2); random u ~ gamma(0, g) subject=s;
run;
proc nlmixed data=obs;
eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=nosuch;
run;
proc nlmixed data=obs;
parms x=1;
eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=s;
run;
proc nlmixed data=obs;
by s;
eta = b0 + u; model y ~ normal(eta, s2); random u ~ normal(0, g) subject=x;
run;
