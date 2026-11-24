/* STAT-LOGISTIC-017: LOGISTIC — Model Fitting Information / Regression Diagnostics
 * Source: S154 / Chapter 79 / `Model Fitting Information` (PDF pp. 5914–5918); S154 / Chapter 79 / `Regression Diagnostics` (PDF pp. 5938–5941).
 * Discriminates: Example 79.6: Logistic Regression Diagnostics
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data vaso;
length Response $12;
input Volume Rate Response @@;
LogVolume=log(Volume);
LogRate=log(Rate);
datalines;
3.70 0.825 constrict 3.50 1.09 constrict
1.25 2.50 constrict 0.75 1.50 constrict
0.80 3.20 constrict 0.70 3.50 constrict
0.60 0.75 no_constrict 1.10 1.70 no_constrict
0.90 0.75 no_constrict 0.90 0.45 no_constrict
0.80 0.57 no_constrict 0.55 2.75 no_constrict
0.60 3.00 no_constrict 1.40 2.33 constrict
0.75 3.75 constrict 2.30 1.64 constrict
3.20 1.60 constrict 0.85 1.415 constrict
1.70 1.06 no_constrict 1.80 1.80 constrict
0.40 2.00 no_constrict 0.95 1.36 no_constrict
1.35 1.35 no_constrict 1.50 1.36 no_constrict
1.60 1.78 constrict 0.60 1.50 no_constrict
1.80 1.50 constrict 0.95 1.90 no_constrict
1.90 0.95 constrict 1.60 0.40 no_constrict
2.70 0.75 constrict 2.35 0.03 no_constrict
1.10 1.83 no_constrict 1.10 2.20 constrict
1.20 2.00 constrict 0.80 3.33 constrict
0.95 1.90 no_constrict 0.75 1.90 no_constrict
1.30 1.625 constrict
;
ods graphics on;
title 'Occurrence of Vasoconstriction';
proc logistic data=vaso;
model Response=LogRate LogVolume/influence;
run;
proc logistic data=vaso plots(only label)=(phat leverage dpc);
model Response=LogRate LogVolume;
run;
data Data1;
input disease n age id $;
datalines;
0 14 25 a
0 20 35 b
0 19 45 c
7 18 55 d
6 12 65 e
17 17 75 f
;
ods graphics on;
%let _ROC_XAXISOPTS_LABEL=False Positive Fraction;
%let _ROC_YAXISOPTS_LABEL=True Positive Fraction;
proc logistic data=Data1 plots(only)=roc(id=id);
model disease/n=age / scale=none
clparm=wald
clodds=pl
rsquare;
units age=10;
id id;
effectplot;
run;
%symdel _ROC_XAXISOPTS_LABEL _ROC_YAXISOPTS_LABEL;
run;
quit;
