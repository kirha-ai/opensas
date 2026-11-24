/* STAT-GAM-001: GAM — Data input, variable roles, and basic options
 * Source: S154 / Chapter 48 / `PROC GAM Statement` (PDF pp. 3296–3298); S154 / Chapter 48 / `BY Statement` (PDF pp. 3298–3299); S154 / Chapter 48 / `FREQ Statement` (PDF p. 3300); S154 / Chapter 48 / `Missing Values` (PDF p. 3307).
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

title 'Patterns of Diabetes';
data diabetes;
input Age BaseDeficit CPeptide @@;
logCP = log(CPeptide);
datalines;
5.2 -8.1 4.8 8.8 -16.1 4.1 10.5 -0.9 5.2
10.6 -7.8 5.5 10.4 -29.0 5.0 1.8 -19.2 3.4
12.7 -18.9 3.4 15.6 -10.6 4.9 5.8 -2.8 5.6
1.9 -25.0 3.7 2.2 -3.1 3.9 4.8 -7.8 4.5
7.9 -13.9 4.8 5.2 -4.5 4.9 0.9 -11.6 3.0
11.8 -2.1 4.6 7.9 -2.0 4.8 11.5 -9.0 5.5
10.6 -11.2 4.5 8.5 -0.2 5.3 11.1 -6.1 4.7
12.8 -1.0 6.6 11.3 -3.6 5.1 1.0 -8.2 3.9
14.5 -0.5 5.7 11.9 -2.0 5.1 8.1 -1.6 5.2
13.8 -11.9 3.7 15.5 -0.7 4.9 9.8 -1.2 4.8
11.0 -14.3 4.4 12.4 -0.8 5.2 11.1 -16.8 5.1
5.1 -5.1 4.6 4.8 -9.5 3.9 4.2 -17.0 5.1
6.9 -3.3 5.1 13.2 -0.7 6.0 9.9 -3.3 4.9
12.5 -13.6 4.1 13.2 -1.9 4.6 8.9 -10.0 4.9
10.8 -13.5 5.1
;
ods graphics on;
data _oracle_input; set diabetes; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc gam data=_oracle_input;
by _oracle_by;
model logCP = spline(Age) spline(BaseDeficit);
run;
