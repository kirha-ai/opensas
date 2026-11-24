/* STAT-ODS-008: ODS destination compatibility scope and the D-022 migration design
 * Source: S154 / Chapter 23 / `Output Objects and ODS Destinations` (PDF pp. 586–587); S154 / Chapter 23 / `The ODS Statement` (PDF pp. 587–588).
 * Discriminates: Real HTML destination creation versus LISTING behavior and observable destination content
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
filename _html temp;
ods html(id=oracle) file=_html style=htmlblue;
proc means data=sample n mean std; var y; run;
ods html(id=oracle) close;
data html_evidence; length line $32767; retain lines 0 has_html 0 has_table 0; infile _html end=eof lrecl=32767 truncover; input line $char32767.; lines+1; has_html=max(has_html,index(lowcase(line),'<html')>0); has_table=max(has_table,index(lowcase(line),'<table')>0); if eof then output; keep lines has_html has_table; run;
proc print data=html_evidence noobs; run;
