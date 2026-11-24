/* STAT-LOGISTIC-022: LOGISTIC — Displayed Output / ODS Table Names
 * Source: S154 / Chapter 79 / `Displayed Output` (PDF pp. 5962–5967); S154 / Chapter 79 / `ODS Table Names` (PDF pp. 5967–5970).
 * Discriminates: Example 79.3: Ordinal Logistic Regression
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods trace on;
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
ods graphics on;
proc logistic data=Cheese plots(only)=oddsratio(range=clip);
freq freq;
class Additive (param=ref ref='4');
model y=Additive / covb nooddsratio;
oddsratio Additive;
effectplot / polybar;
title 'Multiple Response Cheese Tasting Experiment';
run;
proc logistic data=Cheese
plots(only)=effect(x=y sliceby=additive connect yrange=(0,0.4));
freq freq;
class Additive (param=ref ref='4');
model y=Additive / nooddsratio link=alogit;
oddsratio Additive;
title 'Multiple Response Cheese Tasting Experiment';
run;
ods trace off;
