/* STAT-RSREG-006: RSREG — Output Data Sets
 * Source: S154 / Chapter 108 / `Output Data Sets` (PDF pp. 8886–8887).
 * Discriminates: Getting Started: RSREG Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Response Surface with a Simple Optimum';
data smell;
input Odor T R H @@;
label
T = "Temperature"
R = "Gas-Liquid Ratio"
H = "Packing Height";
datalines;
66 40 .3 4 39 120 .3 4 43 40 .7 4 49 120 .7 4
58 40 .5 2 17 120 .5 2 -5 40 .5 6 -40 120 .5 6
65 80 .3 2 7 80 .7 2 43 80 .3 6 -22 80 .7 6
-31 80 .5 4 -35 80 .5 4 -26 80 .5 4
;
proc rsreg data=smell;
model Odor = T R H / lackfit;
run;
ods graphics on;
proc rsreg data=smell
plots(unpack)=surface(3d at(H=7.541050));
model Odor = T R H;
ods select 'T * R = Pred';
run;
ods graphics off;
run;
quit;
