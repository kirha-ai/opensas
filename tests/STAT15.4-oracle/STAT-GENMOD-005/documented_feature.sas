/* STAT-GENMOD-005: GENMOD — DEVIANCE / Generalized Linear Models Theory / Multinomial Models
 * Source: S154 / Chapter 51 / `DEVIANCE Statement` (PDF pp. 3532–3533); S154 / Chapter 51 / `Generalized Linear Models Theory` (PDF pp. 3568–3579); S154 / Chapter 51 / `Multinomial Models` (PDF pp. 3587–3588).
 * Discriminates: Example 51.4: Ordinal Model for Multinomial Data
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
