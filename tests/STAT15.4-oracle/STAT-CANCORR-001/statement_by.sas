/* STAT-CANCORR-001: CANCORR — Data input, variable roles, and basic options
 * Source: S154 / Chapter 34 / `PROC CANCORR Statement` (PDF pp. 2126–2132); S154 / Chapter 34 / `BY Statement` (PDF p. 2132); S154 / Chapter 34 / `FREQ Statement` (PDF pp. 2132–2133); S154 / Chapter 34 / `VAR Statement` (PDF p. 2133); S154 / Chapter 34 / `WEIGHT Statement` (PDF p. 2133); S154 / Chapter 34 / `Missing Values` (PDF p. 2134).
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
data _oracle_input; set Jobs; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc cancorr data=_oracle_input
vprefix=Satisfaction wprefix=Characteristics
vname='Satisfaction Areas' wname='Job Characteristics';
by _oracle_by;
var Career Supervisor Finance;
with Variety Feedback Autonomy;
run;
