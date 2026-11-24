/* STAT-HPNLMOD-007: HPNLMOD — ESTIMATE
 * Source: S154 / Chapter 63 / `ESTIMATE Statement` (PDF pp. 4881–4882).
 * Discriminates: Example 63.1: Segmented Model; explicit statements: ESTIMATE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data a;
input y x @@;
datalines;
.46 1 .47 2 .57 3 .61 4 .62 5 .68 6 .69 7
.78 8 .70 9 .74 10 .77 11 .78 12 .74 13 .80 13
.80 15 .78 16
;
proc hpnlmod data=a out=b;
parms alpha=.45 beta=.05 gamma=-.0025;
x0 = -.5*beta / gamma;
if (x < x0) then
yp = alpha + beta*x + gamma *x*x;
else
yp = alpha + beta*x0 + gamma*x0*x0;
model y ~ residual(yp);
estimate 'join point' -beta/2/gamma;
estimate 'plateau value c' alpha - beta**2/(4*gamma);
predict 'predicted' yp pred=yp;
predict 'response' y pred=y;
predict 'x' x pred=x;
run;
