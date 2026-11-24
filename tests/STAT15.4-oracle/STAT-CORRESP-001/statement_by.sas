/* STAT-CORRESP-001: CORRESP — Data input, variable roles, and basic options
 * Source: S154 / Chapter 41 / `PROC CORRESP Statement` (PDF pp. 2579–2589); S154 / Chapter 41 / `BY Statement` (PDF pp. 2589–2590); S154 / Chapter 41 / `ID Statement` (PDF p. 2590); S154 / Chapter 41 / `VAR Statement` (PDF p. 2591); S154 / Chapter 41 / `WEIGHT Statement` (PDF pp. 2591–2592); S154 / Chapter 41 / `Input Data Set` (PDF p. 2592); S154 / Chapter 41 / `Missing and Invalid Data` (PDF p. 2601).
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

title "Number of Ph.D.'s Awarded from 1973 to 1978";
data PhD;
input Science $ 1-19 y1973-y1978;
label y1973 = '1973'
y1974 = '1974'
y1975 = '1975'
y1976 = '1976'
y1977 = '1977'
y1978 = '1978';
datalines;
Life Sciences       4489 4303 4402 4350 4266 4361
Physical Sciences   4101 3800 3749 3572 3410 3234
Social Sciences     3354 3286 3344 3278 3137 3008
Behavioral Sciences 2444 2587 2749 2878 2960 3049
Engineering         3338 3144 2959 2791 2641 2432
Mathematics         1222 1196 1149 1003 959 959
;
ods graphics on;
data _oracle_input; set PhD; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc corresp data=_oracle_input out=Results short chi2p;
by _oracle_by;
var y1973-y1978;
id Science;
run;
