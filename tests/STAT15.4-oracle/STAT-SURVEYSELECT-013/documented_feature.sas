/* STAT-SURVEYSELECT-013: SURVEYSELECT — Sample Output Data Set / Allocation Output Data Set / Random Assignment Output Data Set
 * Source: S154 / Chapter 124 / `Sample Output Data Set` (PDF pp. 10261–10265); S154 / Chapter 124 / `Allocation Output Data Set` (PDF pp. 10265–10266); S154 / Chapter 124 / `Random Assignment Output Data Set` (PDF pp. 10266–10267).
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

data TravelExpense;
input ID$ Amount @@;
if (Amount < 500) then Level='1_Low ';
else if (Amount > 1500) then Level='3_High';
else Level='2_Avg ';
datalines;
110 237.18 002 567.89 234 118.50
743 74.38 411 1287.23 782 258.10
216 325.36 174 218.38 568 1670.80
302 134.71 285 2020.70 314 47.80
139 1183.45 775 330.54 425 780.10
506 895.80 239 620.10 011 420.18
672 979.66 142 810.25 738 670.85
192 314.58 243 87.50 263 1893.40
496 753.30 332 540.65 486 2580.35
614 230.56 654 185.60 308 688.43
784 505.14 017 205.48 162 650.42
289 1348.34 691 30.50 545 2214.80
517 940.35 382 217.85 024 142.90
478 806.90 107 560.72
;
proc sort data=TravelExpense;
by Level;
run;
title1 'Travel Expense Audit';
title2 'Stratified PPS (Dollar-Unit) Sampling';
proc surveyselect data=TravelExpense method=pps n=(6 10 4)
seed=47279 out=AuditSample;
size Amount;
strata Level;
run;
title1 'Travel Expense Audit';
title2 'Sample Selected by Stratified PPS Design';
proc print data=AuditSample;
run;
