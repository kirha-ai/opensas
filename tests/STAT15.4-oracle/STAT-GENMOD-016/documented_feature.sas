/* STAT-GENMOD-016: GENMOD — CODE / Predicted Values of the Mean
 * Source: S154 / Chapter 51 / `CODE Statement` (PDF pp. 3529–3530); S154 / Chapter 51 / `Predicted Values of the Mean` (PDF pp. 3585–3586).
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

data nor;
input x y;
datalines;
0 5
0 7
0 9
1 7
1 10
1 8
2 11
2 9
3 16
3 13
3 14
4 25
4 24
5 34
5 32
5 30
;
proc genmod data=nor;
model y = x / dist = normal
link = log;
output out = Residuals
pred = Pred
resraw = Resraw
reschi = Reschi
resdev = Resdev
stdreschi = Stdreschi
stdresdev = Stdresdev
reslik = Reslik;
run;
