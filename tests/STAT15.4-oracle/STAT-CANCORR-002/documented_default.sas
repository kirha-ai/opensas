/* STAT-CANCORR-002: CANCORR — Canonical correlation analysis between two variable sets
 * Source: S154 / Chapter 34 / `Getting Started: CANCORR Procedure` (PDF pp. 2121–2126); S154 / Chapter 34 / `Overview: CANCORR Procedure` (PDF pp. 2120–2121).
 * Discriminates: Getting Started: CANCORR Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Jobs;
input Career Supervisor Finance Variety Feedback Autonomy;
label Career ='Career Satisfaction' Variety ='Task Variety'
Supervisor='Supervisor Satisfaction' Feedback='Amount of Feedback'
Finance ='Financial Satisfaction' Autonomy='Degree of Autonomy';
datalines;
72 26 9 10 11 70
63 76 7 85 22 93
96 31 7 83 63 73
96 98 6 82 75 97
84 94 6 36 77 97
66 10 5 28 24 75
31 40 9 64 23 75
45 14 2 19 15 50
42 18 6 33 13 70
79 74 4 23 14 90
39 12 2 37 13 70
54 35 3 23 74 53
60 75 5 45 58 83
63 45 5 22 67 53
;
proc cancorr data=Jobs
vprefix=Satisfaction wprefix=Characteristics
vname='Satisfaction Areas' wname='Job Characteristics';
var Career Supervisor Finance;
with Variety Feedback Autonomy;
run;
