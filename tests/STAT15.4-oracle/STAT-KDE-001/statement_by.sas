/* STAT-KDE-001: KDE — Data input, variable roles, and basic options
 * Source: S154 / Chapter 73 / `PROC KDE Statement` (PDF pp. 5393–5394); S154 / Chapter 73 / `BY Statement` (PDF p. 5398); S154 / Chapter 73 / `FREQ Statement` (PDF pp. 5398–5399); S154 / Chapter 73 / `WEIGHT Statement` (PDF p. 5405).
 * Discriminates: Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results.
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
data _oracle_input; set bivnormal; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc kde data=_oracle_input;
by _oracle_by;
bivar x y / plots=(contour surface);
run;
ods graphics off;

run; quit;
