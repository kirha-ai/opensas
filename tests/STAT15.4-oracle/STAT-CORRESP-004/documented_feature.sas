/* STAT-CORRESP-004: CORRESP — Using the VAR / Coding, Fuzzy Coding, and Doubling / Creating a Data Set Containing the Crosstabulation
 * Source: S154 / Chapter 41 / `Using the VAR Statement` (PDF pp. 2600–2601); S154 / Chapter 41 / `Coding, Fuzzy Coding, and Doubling` (PDF pp. 2601–2604); S154 / Chapter 41 / `Creating a Data Set Containing the Crosstabulation` (PDF pp. 2604–2606).
 * Discriminates: Getting Started: CORRESP Procedure
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
proc corresp data=PhD out=Results short chi2p;
var y1973-y1978;
id Science;
run;
