/* STAT-GENMOD-004: GENMOD — Specification of Effects / Parameterization Used in PROC GENMOD / Response Level Ordering
 * Source: S154 / Chapter 51 / `Specification of Effects` (PDF pp. 3579–3580); S154 / Chapter 51 / `Parameterization Used in PROC GENMOD` (PDF pp. 3580–3581); S154 / Chapter 51 / `Response Level Ordering` (PDF pp. 3615–3616).
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
