/* STAT-TTEST-012: TTEST — Official examples and feature integration regression
 * Source: S154 / Chapter 128 / `Examples: TTEST Procedure` (PDF pp. 10650–10689).
 * Discriminates: Summary-statistics input, PROC MEANS handoff and two-group TTEST integration
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data asthma; input drug1 $ drug2 $ pef1 pef2 @@; datalines;
for sal 310 270 for sal 310 260 for sal 370 300
for sal 410 390 for sal 250 210 for sal 380 350
for sal 330 365
sal for 370 385 sal for 310 400 sal for 380 410
sal for 290 320 sal for 260 340 sal for 90 220
;
run;
proc sort data=asthma; by drug1; run;
proc means data=asthma noprint; var pef1; by drug1; output out=summary; run;
proc print data=summary noobs; run;
proc ttest data=summary; class drug1; var pef1; run;
