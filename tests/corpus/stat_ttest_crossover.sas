/* STAT-TTEST-008: TTEST — AB/BA Crossover Design
 * Source: S154 / Chapter 128 / `AB/BA Crossover Design` (PDF pp. 10629–10630).
 * Discriminates: AB/BA treatment and period effects using Example 128.4 input
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
proc ttest data=asthma; var pef1 pef2 / crossover=(drug1 drug2); run;
