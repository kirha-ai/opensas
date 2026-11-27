/* STAT-LOGISTIC-008: LOGISTIC — Classification Table / Goodness-of-Fit Tests / Overdispersion
 * Source: S154 / Chapter 79 / `Classification Table` (PDF pp. 5926–5929); S154 / Chapter 79 / `Goodness-of-Fit Tests` (PDF pp. 5929–5932); S154 / Chapter 79 / `Overdispersion` (PDF pp. 5932–5934).
 * Discriminates: Example 79.9: Goodness-of-Fit Tests and Subpopulations
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data One;
do A=0,1;
do B=0,1;
do Y=1,2;
input F @@;
output;
end;
end;
end;
datalines;
23 63 31 70 67 100 70 104
;
proc logistic data=One;
freq F;
model Y=A B A*B;
run;
proc logistic data=One;
freq F;
model Y=A / scale=none aggregate=(A B);
run;
