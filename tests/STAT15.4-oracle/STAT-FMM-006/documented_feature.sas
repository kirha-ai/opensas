/* STAT-FMM-006: FMM — Overdispersion / Log-Likelihood Functions for Response Distributions / Conjugate Sampling
 * Source: S154 / Chapter 46 / `Overdispersion` (PDF pp. 3018–3019); S154 / Chapter 46 / `Log-Likelihood Functions for Response Distributions` (PDF pp. 3019–3026); S154 / Chapter 46 / `Conjugate Sampling` (PDF pp. 3026–3027).
 * Discriminates: Example 46.4: Modeling Multinomial Overdispersion: Town and Country
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data housing;
label us = 'Unsatisfied'
s = 'Satisfied'
vs = 'Very Satisfied';
input type $ us s vs @@;
datalines;
rural 3 2 0 rural 3 2 0 rural 0 5 0 rural 3 2 0 rural 0 5 0
rural 4 1 0 rural 3 2 0 rural 2 3 0 rural 4 0 1 rural 0 4 1
rural 2 3 0 rural 4 1 0 rural 4 1 0 rural 1 2 2 rural 4 1 0
rural 1 3 1 rural 4 1 0 rural 5 0 0
urban 0 4 1 urban 0 5 0 urban 0 3 2 urban 3 2 0 urban 2 3 0
urban 1 3 1 urban 4 1 0 urban 4 0 1 urban 0 3 2 urban 1 2 2
urban 0 5 0 urban 3 2 0 urban 2 3 0 urban 2 2 1 urban 4 0 1
urban 0 4 1 urban 4 1 0
;
proc fmm data=housing seed=314159;
class type;
model us s vs = Type / dist=multinomial;
output out=Pred pred;
run;
data Pred;
set Pred;
Pred_1 = Pred_1 / (us + s + vs);
Pred_2 = Pred_2 / (us + s + vs);
Pred_3 = Pred_3 / (us + s + vs);
run;
proc sort data=Pred nodupkey;
by type;
proc print data=pred noobs;
var type pred:;
run;
proc fmm data=housing seed=314159;
class type;
model us s vs = Type / dist=multinomcluster;
output out=Pred pred;
probmodel Type;
run;
