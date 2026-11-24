/* STAT-PLM-005: PLM — Analysis Based on Posterior Estimates
 * Source: S154 / Chapter 94 / `Analysis Based on Posterior Estimates` (PDF pp. 7646–7648).
 * Discriminates: Example 94.7: Linear Inference with Arbitrary Estimates
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data parms;
length name $6;
input Name$ Value;
datalines;
alpha1 -3.5671
beta1 0.4421
gamma1 -2.6230
alpha2 -3.0111
beta2 0.3977
gamma2 -2.4442
;
data cov;
input Parm row col1-col6;
datalines;
1 1 0.007462 -0.005222 0.010234 0.000000 0.000000 0.000000
1 2 -0.005222 0.048197 -0.010590 0.000000 0.000000 0.000000
1 3 0.010234 -0.010590 0.215999 0.000000 0.000000 0.000000
1 4 0.000000 0.000000 0.000000 0.031261 -0.009096 0.015785
1 5 0.000000 0.000000 0.000000 -0.009096 0.039487 -0.019996
1 6 0.000000 0.000000 0.000000 0.015785 -0.019996 0.126172
;
proc glimmix data=parms order=data;
class Name;
model Value = Name / noint ddfm=none s;
random _residual_ / type=lin(1) ldata=cov v;
parms (1) / noiter;
store ArtificialModel;
title 'Linear Inference';
run;
proc plm restore=ArtificialModel;
estimate
'alpha1 = alpha2' Name 1 0 0 -1 0 0,
'beta1 = beta2 ' Name 0 1 0 0 -1 0,
'gamma1 = gamma2' Name 0 0 1 0 0 -1 /
adjust=bon stepdown ftest(label='Homogeneity');
run;
