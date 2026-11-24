/* STAT-STDIZE-002: STDIZE — Variable standardization and location/scale estimation
 * Source: S154 / Chapter 115 / `Getting Started: STDIZE Procedure` (PDF pp. 9448–9455); S154 / Chapter 115 / `Overview: STDIZE Procedure` (PDF p. 9448).
 * Discriminates: Within-group standardization, reported location/scale and transformed values
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data sample;
 input x z y group $ weight freq;
 datalines;
1 1 4 A 1 1
2 1 6 A 2 1
3 2 7 A 1 2
4 1 9 A 1 1
5 3 13 A 2 1
6 2 12 A 1 1
7 4 17 B 1 1
8 3 19 B 2 2
9 5 20 B 1 1
10 3 23 B 1 1
11 5 25 B 2 1
12 4 24 B 1 1
;
run;
proc sort data=sample; by group; run;
proc stdize data=sample out=standardized method=std pstat; by group; var x z y; run;
proc print data=standardized noobs; format _numeric_ best32.; run;
