/* STAT-MIXED-016: MIXED — Default Output / ODS Table Names
 * Source: S154 / Chapter 84 / `Default Output` (PDF pp. 6720–6724); S154 / Chapter 84 / `ODS Table Names` (PDF pp. 6724–6729).
 * Discriminates: Getting Started: MIXED Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods trace on;
data heights;
input Family Gender$ Height @@;
datalines;
1 F 67 1 F 66 1 F 64 1 M 71 1 M 72 2 F 63
2 F 63 2 F 67 2 M 69 2 M 68 2 M 70 3 F 63
3 M 64 4 F 67 4 F 66 4 M 67 4 M 67 4 M 69
;
proc mixed data=heights;
class Family Gender;
model Height = Gender Family Family*Gender;
run;
proc mixed;
class Family Gender;
model Height = Gender;
random Family Family*Gender;
run;
ods trace off;
