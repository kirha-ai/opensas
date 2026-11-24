/* STAT-MIXED-019: MIXED — Official examples and feature integration regression
 * Source: S154 / Chapter 84 / `Examples: MIXED Procedure` (PDF pp. 6738–6802).
 * Discriminates: Example 84.9: Examining Individual Test Components
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data polynomial;
do x=1 to 20;
input y@@;
output;
end;
datalines;
1.092 1.758 1.997 3.154 3.880
3.810 4.921 4.573 6.029 6.032
6.291 7.151 7.154 6.469 7.137
6.374 5.860 4.866 4.155 2.711
;
proc mixed data=polynomial;
model y = x x*x x*x*x / s lcomponents htype=1,3;
run;
