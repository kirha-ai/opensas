/* STAT-ORTHOREG-010: ORTHOREG — Official examples and feature integration regression
 * Source: S154 / Chapter 91 / `Examples: ORTHOREG Procedure` (PDF pp. 7300–7309).
 * Discriminates: Example 91.3: Fitting Polynomials
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Polynomial Data';
data Polynomial;
do i = 1 to 101;
x = (i-1)/(101-1);
y = 10**(9/2);
do j = 0 to 8;
y = y * (x - j/8);
end;
output;
end;
run;
ods graphics on;
proc orthoreg data=Polynomial;
effect xMod = polynomial(x / degree=9);
model y = xMod;
effectplot fit / obs;
store OStore;
run;
ods graphics off;
data Zeros(keep=x);
do j = 0 to 8;
x = j/8;
output;
end;
run;
proc plm restore=OStore noprint;
score data=Zeros out=OZeros pred=OPred;
run;
proc print noobs;
run;
proc glm data=Polynomial;
model y = x|x|x|x|x|x|x|x|x;
store GStore;
run;
