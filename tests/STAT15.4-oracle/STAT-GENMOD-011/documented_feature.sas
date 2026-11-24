/* STAT-GENMOD-011: GENMOD — CONTRAST / ESTIMATE / Type 1 Analysis
 * Source: S154 / Chapter 51 / `CONTRAST Statement` (PDF pp. 3530–3532); S154 / Chapter 51 / `ESTIMATE Statement` (PDF pp. 3534–3535); S154 / Chapter 51 / `Type 1 Analysis` (PDF pp. 3581–3582).
 * Discriminates: Example 51.4: Ordinal Model for Multinomial Data; explicit statements: ESTIMATE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Icecream;
input count brand$ taste$;
datalines;
70 ice1 vg
71 ice1 g
151 ice1 m
30 ice1 b
46 ice1 vb
20 ice2 vg
36 ice2 g
130 ice2 m
74 ice2 b
70 ice2 vb
50 ice3 vg
55 ice3 g
140 ice3 m
52 ice3 b
50 ice3 vb
;
proc genmod data=Icecream rorder=data;
freq count;
class brand;
model taste = brand / dist=multinomial
link=cumlogit
aggregate=brand
type1;
estimate 'LogOR12' brand 1 -1 / exp;
estimate 'LogOR13' brand 1 0 -1 / exp;
estimate 'LogOR23' brand 0 1 -1 / exp;
run;
