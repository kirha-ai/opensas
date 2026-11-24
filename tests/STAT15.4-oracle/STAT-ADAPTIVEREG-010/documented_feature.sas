/* STAT-ADAPTIVEREG-010: ADAPTIVEREG — Computational Resources
 * Source: S154 / Chapter 28 / `Computational Resources` (PDF pp. 1080–1082).
 * Discriminates: Verified default procedure context
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Mixture;
drop i;
do i=1 to 1000;
X1 = ranuni(1);
C1 = int(3*ranuni(1));
if C1=0 then Y=exp(5*(X1-0.3)**2)+rannor(1);
else if C1=1 then Y=log(X1*(1-X1))+rannor(1);
else Y=7*X1+rannor(1);
output;
end;
run;
ods graphics on;
proc adaptivereg data=Mixture plots=fit;
class c1;
model y=c1 x1;
run;
proc adaptivereg data=Mixture details=bases;
class c1;
model y=c1 x1;
run;
data New;
set Mixture;
basis1 = (c1=1 OR c1=0);
basis3 = (c1=1);
basis5 = NOT(c1=1) *MAX(x1-0.7665019053,0);
basis7 = NOT(c1=1 OR c1=0) *MAX(x1-0.7665019053,0);
basis8 = NOT(c1=1 OR c1=0) *MAX(0.7665019053-x1,0);
basis9 = (c1=1) *MAX(x1-0.5530566455,0);
basis10 = (c1=1)*MAX(0.5530566455-x1,0);
basis11 = (c1=1)*MAX(x1-0.045800759,0);
basis13 = (c1=1)*MAX(x1-0.9526330293,0);
basis15 = (c1=1 OR c1=0)*MAX(x1-0.9499325226,0);
basis17 = (c1=1 OR c1=0)*MAX(x1-0.5142821095,0);
basis19 = (c1=1 OR c1=0)*MAX(x1-0.9889635476,0);
pred = 5.3829 - 4.3871 *basis1 + 32.7761*basis3 +
20.2859*basis5 - 11.4183*basis7 - 7.0758*basis8 +
58.4911*basis9 - 71.6388*basis10 - 69.0764*basis11 -
119.71*basis13 + 66.5733*basis15 + 6.6681*basis17 -
185.21*basis19;
run;
