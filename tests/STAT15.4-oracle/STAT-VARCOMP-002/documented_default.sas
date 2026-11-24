/* STAT-VARCOMP-002: VARCOMP — Variance component estimation
 * Source: S154 / Chapter 130 / `Getting Started: VARCOMP Procedure` (PDF pp. 10727–10729); S154 / Chapter 130 / `Overview: VARCOMP Procedure` (PDF pp. 10726–10727).
 * Discriminates: Getting Started: VARCOMP Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Cure;
input Lab Temp Batch $ Cure @@;
datalines;
1 145 A 18.6 1 145 A 17.0 1 145 A 18.7 1 145 A 18.7
1 145 B 14.5 1 145 B 15.8 1 145 B 16.5 1 145 B 17.6
1 145 C 21.1 1 145 C 20.8 1 145 C 21.8 1 145 C 21.0
1 155 A 9.5 1 155 A 9.4 1 155 A 9.5 1 155 A 10.0
1 155 B 7.8 1 155 B 8.3 1 155 B 8.9 1 155 B 9.1
1 155 C 11.2 1 155 C 10.0 1 155 C 11.5 1 155 C 11.1
1 165 A 5.4 1 165 A 5.3 1 165 A 5.7 1 165 A 5.3
1 165 B 5.2 1 165 B 4.9 1 165 B 4.3 1 165 B 5.2
1 165 C 6.3 1 165 C 6.4 1 165 C 5.8 1 165 C 5.6
2 145 A 20.0 2 145 A 20.1 2 145 A 19.4 2 145 A 20.0
2 145 B 18.4 2 145 B 18.1 2 145 B 16.5 2 145 B 16.7
2 145 C 22.5 2 145 C 22.7 2 145 C 21.5 2 145 C 21.3
2 155 A 11.4 2 155 A 11.5 2 155 A 11.4 2 155 A 11.5
2 155 B 10.8 2 155 B 11.1 2 155 B 9.5 2 155 B 9.7
2 155 C 13.3 2 155 C 14.0 2 155 C 12.0 2 155 C 11.5
2 165 A 6.8 2 165 A 6.9 2 165 A 6.0 2 165 A 5.7
2 165 B 6.0 2 165 B 6.1 2 165 B 5.0 2 165 B 5.2
2 165 C 7.7 2 165 C 8.0 2 165 C 6.6 2 165 C 6.3
3 145 A 19.7 3 145 A 18.3 3 145 A 16.8 3 145 A 17.1
3 145 B 16.3 3 145 B 16.7 3 145 B 14.4 3 145 B 15.2
3 145 C 22.7 3 145 C 21.9 3 145 C 19.3 3 145 C 19.3
3 155 A 9.3 3 155 A 10.2 3 155 A 9.8 3 155 A 9.5
3 155 B 9.1 3 155 B 9.2 3 155 B 8.0 3 155 B 9.0
3 155 C 11.3 3 155 C 11.0 3 155 C 10.9 3 155 C 11.4
3 165 A 6.7 3 165 A 6.0 3 165 A 5.0 3 165 A 4.8
3 165 B 5.7 3 165 B 5.5 3 165 B 4.6 3 165 B 5.4
3 165 C 6.6 3 165 C 6.5 3 165 C 5.9 3 165 C 5.8
;
title 'Analyzing the Cure Rate of Rubber';
proc varcomp method=reml data=cure;
class temp lab batch;
model cure=temp|lab batch(lab temp) / fixed=1;
run;
