/* STAT-DISTANCE-001: the ticket's documented_feature program, complete and
 * unchanged (PROC DISTANCE METHOD=EUCLID OUT= with STD=STD interval
 * variables, then PROC PRINT NOOBS of the OUT= matrix). Invented data.
 * Expected output: every token (header names and all 144 cell values, in
 * order) is the SAS 9.4 reference listing of this program, checked token by
 * token; only the inter-column spacing is opensas's PROC PRINT layout, whose
 * SAS column spacing is the open STAT-PRINT-001 gap (d).
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
proc distance data=sample method=euclid out=dist;
var interval(x z /std=std);
run;
proc print data=dist noobs;
run;
