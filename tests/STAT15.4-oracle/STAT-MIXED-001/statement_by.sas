/* STAT-MIXED-001: MIXED — Data input, variable roles, and basic options
 * Source: S154 / Chapter 84 / `PROC MIXED Statement` (PDF pp. 6626–6638); S154 / Chapter 84 / `BY Statement` (PDF pp. 6638–6639); S154 / Chapter 84 / `ID Statement` (PDF pp. 6645–6646); S154 / Chapter 84 / `WEIGHT Statement` (PDF pp. 6694–6695).
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

data heights;
input Family Gender$ Height @@;
datalines;
1 F 67 1 F 66 1 F 64 1 M 71 1 M 72 2 F 63
2 F 63 2 F 67 2 M 69 2 M 68 2 M 70 3 F 63
3 M 64 4 F 67 4 F 66 4 M 67 4 M 67 4 M 69
;
data _oracle_input; set heights; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc mixed data=_oracle_input;
by _oracle_by;
class Family Gender;
model Height = Gender Family Family*Gender;
run;
proc mixed;
class Family Gender;
model Height = Gender;
random Family Family*Gender;
run;
