/* STAT-KDE-001: the chapter's Getting Started bivariate example (PDF p.5378,
 * SAS sample program; data from RANNOR) with PLOTS=NONE, the only change from
 * the documented program: default Inputs and Controls tables (Figure 73.3).
 * Expected listing: the SAS 9.4 reference listing of the original program. */
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
bivar x y / plots=none;
run;
ods graphics off;
run;
quit;
