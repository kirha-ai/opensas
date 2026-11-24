/* STAT-HPREG-013: HPREG — Official examples and feature integration regression
 * Source: S154 / Chapter 67 / `Examples: HPREG Procedure` (PDF pp. 5052–5067).
 * Discriminates: Example 67.2: Forward-Swap Selection
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data ex3Data;
array x{20};
do i=1 to 10000;
do j=1 to 20;
x{j} = ranuni(1);
end;
y = 3*x1 + 7*x2 -5*x3 + 5*x1*x3 +
4*x2*x13 + x7 + x11 -x13 + x1 *x4 + rannor(1);
output;
end;
run;
proc hpreg data=ex3Data;
model y = x1|x2|x3|x4|x5|x6|x7|x8|x9|x10|X11|
x12|x13|x14|x5|x16|x7|x18|x19|x20@2 /
include=(x1 x2 x3) start=(x1*x2 x1*x3 x2*x3);
selection method=forwardswap(select=rsquare maxef=15 choose=sbc)
details=all;
run;
