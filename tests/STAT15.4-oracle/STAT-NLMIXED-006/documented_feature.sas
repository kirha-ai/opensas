/* STAT-NLMIXED-006: NLMIXED — Built-In Log-Likelihood Functions / Compartment Models / Hierarchical Model Specification
 * Source: S154 / Chapter 89 / `Built-In Log-Likelihood Functions` (PDF pp. 7131–7134); S154 / Chapter 89 / `Compartment Models` (PDF pp. 7134–7144); S154 / Chapter 89 / `Hierarchical Model Specification` (PDF pp. 7144–7146).
 * Discriminates: Normal likelihood with nested cluster/person random effects and predictions.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data repeated;
call streaminit(314159);
do cluster=1 to 8;
 u0=0.5*rand('normal');
 do j=1 to 4;
 person=cluster*10+j; v0=0.3*rand('normal');
 do visit=1 to 3;
 x=visit/3; y=2+1.2*x+u0+v0+0.4*rand('normal'); output;
 end; end;
end;
drop u0 v0 j;
run;
proc nlmixed data=repeated qpoints=3 maxiter=100;
parms b0=2 b1=1 s1=0.25 s2=0.09 se=0.16;
bounds s1 s2 se > 0;
mu=b0+b1*x+u+v;
model y ~ normal(mu,se);
random u ~ normal(0,s1) subject=cluster;
random v ~ normal(0,s2) subject=person(cluster);
predict mu out=predicted;
run;
proc print data=predicted(obs=10); run;
