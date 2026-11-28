/* expect-rc: 2
 * STAT-HPGENSELECT-001: valid PROC HPGENSELECT features owned by later
 * HPGENSELECT and shared high-performance tickets must fail visibly (D-009
 * gap) without printing a partial analysis: the default NORMAL distribution,
 * other distributions and links, SELECTION, OUTPUT, PARTITION, PERFORMANCE,
 * CODE, RESTRICT and ZEROMODEL statements, optimization and output options,
 * CLASS options, response options, events/trials, crossed effects, MODEL
 * options such as OFFSET= and NOINT, FREQ with WEIGHT, a FORMAT statement,
 * a CLASS response, an intercept-only model and a BY group without usable
 * observations. Invented data.
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
proc hpgenselect data=cnt; class g; model y = g x; run;
proc hpgenselect data=cnt; model y = x / dist=normal; run;
proc hpgenselect data=cnt; model y = x / dist=nb; run;
proc hpgenselect data=cnt; model y = x / dist=poisson link=identity; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; selection method=forward; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; output out=o pred=p; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; partition fraction(validate=0.3); run;
proc hpgenselect data=cnt; model y = x / dist=poisson; performance nthreads=1; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; code file='x.sas'; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; zeromodel x; run;
proc hpgenselect data=cnt maxiter=10; model y = x / dist=poisson; run;
proc hpgenselect data=cnt itdetails; model y = x / dist=poisson; run;
proc hpgenselect data=cnt; class g(ref=first); model y = g x / dist=poisson; run;
proc hpgenselect data=cnt; model y(event='1') = x / dist=poisson; run;
proc hpgenselect data=cnt; model y/f = x / dist=binomial; run;
proc hpgenselect data=cnt; class g; model y = g*x / dist=poisson; run;
proc hpgenselect data=cnt; model y = x / dist=poisson offset=w; run;
proc hpgenselect data=cnt; model y = x / dist=poisson noint; run;
proc hpgenselect data=cnt; model y = x / dist=poisson; freq f; weight w; run;
proc hpgenselect data=cnt; class g; model y = g x / dist=poisson; format g 8.; run;
proc hpgenselect data=cnt; class g; model g = x / dist=poisson; run;
proc hpgenselect data=cnt; model y = / dist=poisson; run;
data byempty; set cnt; b=(g=2); if b then x=.; run;
proc sort data=byempty; by b; run;
proc hpgenselect data=byempty; by b; model y = x / dist=poisson; run;
