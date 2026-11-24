/* STAT-HPLOGISTIC-009: HPLOGISTIC — OUTPUT
 * Source: S154 / Chapter 61 / `OUTPUT Statement` (PDF pp. 4760–4762).
 * Discriminates: Example 61.3: Ordinal Logistic Regression; explicit statements: OUTPUT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Cheese;
do Additive = 1 to 4;
do y = 1 to 9;
input freq @@;
output;
end;
end;
label y='Taste Rating';
datalines;
0 0 1 7 8 8 19 8 1
6 9 12 11 7 6 1 0 0
1 1 6 8 23 7 5 1 0
0 0 0 1 3 7 14 16 11
;
proc hplogistic data=Cheese;
freq freq;
class Additive(ref='4') / param=ref ;
model y=Additive;
title 'Multiple Response Cheese Tasting Experiment';
run;
