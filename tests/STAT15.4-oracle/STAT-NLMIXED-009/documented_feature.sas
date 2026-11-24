/* STAT-NLMIXED-009: NLMIXED — BOUNDS / PARMS / Restricting the Step Length
 * Source: S154 / Chapter 89 / `BOUNDS Statement` (PDF pp. 7116–7117); S154 / Chapter 89 / `PARMS Statement` (PDF pp. 7122–7123); S154 / Chapter 89 / `Restricting the Step Length` (PDF pp. 7156–7157).
 * Discriminates: Explicit PARMS starting values and lower BOUNDS on positive variance parameters.
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
proc nlmixed data=repeated qpoints=5 maxiter=100;
parms b0=2 b1=1 s1=0.25 se=0.25;
bounds s1 >= 0.001, se >= 0.001;
mu=b0+b1*x+u;
model y ~ normal(mu,se);
random u ~ normal(0,s1) subject=cluster;
run;
