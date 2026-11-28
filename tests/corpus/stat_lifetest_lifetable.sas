/* STAT-LIFETEST-003: life-table (actuarial) estimates with explicit
 * INTERVALS= and FREQ counts for one sample. The program is the published
 * guide example (SAS/STAT 15.4 Example 77.3, grouped angina pectoris counts)
 * without its PLOTS= request and ODS GRAPHICS, which belong to the LIFETEST
 * graph ticket. Expected listing: the SAS reference listing of the example.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Survival of Males with Angina Pectoris';
data Males;
keep Freq Years Censored;
retain Years -.5;
input fail withdraw @@;
Years + 1;
Censored=0;
Freq=fail;
output;
Censored=1;
Freq=withdraw;
output;
datalines;
456 0 226 39 152 22 171 23 135 24 125 107
83 133 74 102 51 68 42 64 43 45 34 53
18 33 9 27 6 23 0 30
;
proc lifetest data=Males method=lt intervals=(0 to 15 by 1);
time Years*Censored(1);
freq Freq;
run;
ods graphics off;
run;
quit;
