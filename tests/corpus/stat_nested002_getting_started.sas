/* STAT-NESTED-002: Getting Started default analysis of PROC NESTED (SAS/STAT
 * 15.4 NESTED chapter, published Auto reliability sample data): balanced
 * two-stage nested random-effects design CLASS Make Model, VAR Score after
 * PROC SORT, with the batch harness preamble (ODS LISTING, PROC DATASETS
 * KILL). Principal estimates: variance components 33.867284 (Make),
 * 83.425926 (Model), 14.583333 (Error); 36 observations enter (Total DF 35).
 * The expected listing is the SAS 15.4 reference output of this program.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data auto;
input Make $ Model Score @@;
datalines;
a 1 62 a 2 77 a 3 59
a 1 67 a 2 73 a 3 64
a 1 60 a 2 79 a 3 60
b 1 72 b 2 58 b 3 80
b 1 75 b 2 63 b 3 84
b 1 69 b 2 57 b 3 89
c 1 94 c 2 76 c 3 81
c 1 90 c 2 75 c 3 85
c 1 88 c 2 78 c 3 85
d 1 69 d 2 73 d 3 90
d 1 72 d 2 88 d 3 87
d 1 76 d 2 87 d 3 92
;
proc sort data=auto;
by Make Model;
run;
title1 'Reliability of Automobile Models';
proc nested data=auto;
class Make Model;
var Score;
run;
quit;
