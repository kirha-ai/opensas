/* STAT-LOGISTIC-012: LOGISTIC — ROC / ROCCONTRAST / Receiver Operating Characteristic Curves
 * Source: S154 / Chapter 79 / `ROC Statement` (PDF pp. 5896–5897); S154 / Chapter 79 / `ROCCONTRAST Statement` (PDF pp. 5897–5898); S154 / Chapter 79 / `Receiver Operating Characteristic Curves` (PDF pp. 5934–5937).
 * Discriminates: Example 79.8: Comparing Receiver Operating Characteristic Curves; explicit statements: ROC, ROCCONTRAST
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data roc;
input alb tp totscore popind @@;
totscore = 10 - totscore;
datalines;
3.0 5.8 10 0 3.2 6.3 5 1 3.9 6.8 3 1 2.8 4.8 6 0
3.2 5.8 3 1 0.9 4.0 5 0 2.5 5.7 8 0 1.6 5.6 5 1
3.8 5.7 5 1 3.7 6.7 6 1 3.2 5.4 4 1 3.8 6.6 6 1
4.1 6.6 5 1 3.6 5.7 5 1 4.3 7.0 4 1 3.6 6.7 4 0
2.3 4.4 6 1 4.2 7.6 4 0 4.0 6.6 6 0 3.5 5.8 6 1
3.8 6.8 7 1 3.0 4.7 8 0 4.5 7.4 5 1 3.7 7.4 5 1
3.1 6.6 6 1 4.1 8.2 6 1 4.3 7.0 5 1 4.3 6.5 4 1
3.2 5.1 5 1 2.6 4.7 6 1 3.3 6.8 6 0 1.7 4.0 7 0
3.7 6.1 5 1 3.3 6.3 7 1 4.2 7.7 6 1 3.5 6.2 5 1
2.9 5.7 9 0 2.1 4.8 7 1 2.8 6.2 8 0 4.0 7.0 7 1
3.3 5.7 6 1 3.7 6.9 5 1 3.6 6.6 5 1
;
ods graphics on;
proc logistic data=roc plots=roc(id=prob);
model popind(event='0') = alb tp totscore / nofit;
roc 'Albumin' alb;
roc 'K-G Score' totscore;
roc 'Total Protein' tp;
roccontrast reference('K-G Score') / estimate e;
run;
