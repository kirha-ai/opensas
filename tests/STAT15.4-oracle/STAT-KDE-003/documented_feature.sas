/* STAT-KDE-003: KDE — BIVAR / UNIVAR / Computational Overview
 * Source: S154 / Chapter 73 / `BIVAR Statement` (PDF pp. 5394–5398); S154 / Chapter 73 / `UNIVAR Statement` (PDF pp. 5401–5405); S154 / Chapter 73 / `Computational Overview` (PDF pp. 5405–5406).
 * Discriminates: Getting Started: KDE Procedure; explicit statements: BIVAR
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data bivnormal;
seed = 1283470;
do i = 1 to 1000;
z1 = rannor(seed);
z2 = rannor(seed);
z3 = rannor(seed);
x = 3*z1+z2;
y = 3*z1+z3;
output;
end;
drop seed;
run;
ods graphics on;
proc kde data=bivnormal;
bivar x y / plots=(contour surface);
run;
ods graphics off;
run;
quit;
