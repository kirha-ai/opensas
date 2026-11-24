/* STAT-KDE-004: KDE — Kernel Density Estimates / Binning / Kernel Distribution Estimates
 * Source: S154 / Chapter 73 / `Kernel Density Estimates` (PDF pp. 5406–5407); S154 / Chapter 73 / `Binning` (PDF pp. 5407–5409); S154 / Chapter 73 / `Kernel Distribution Estimates` (PDF pp. 5409–5411).
 * Discriminates: Example 73.5: Univariate KDE Graphics
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
univar x / plots=(density histogram histdensity);
univar x y / plots=densityoverlay;
run;
ods graphics off;
run;
quit;
