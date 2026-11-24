/* STAT-ANOVA-006: ANOVA — MANOVA / TEST
 * Source: S154 / Chapter 29 / `MANOVA Statement` (PDF pp. 1119–1123); S154 / Chapter 29 / `TEST Statement` (PDF pp. 1134–1135).
 * Discriminates: Example 29.3: Split Plot; explicit statements: TEST
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title1 'Split Plot Design';
data Split;
input Block 1 A 2 B 3 Response;
datalines;
142 40.0
141 39.5
112 37.9
111 35.4
121 36.7
122 38.2
132 36.4
131 34.8
221 42.7
222 41.6
212 40.3
211 41.6
241 44.5
242 47.6
231 43.6
232 42.8
;
proc anova data=Split;
class Block A B;
model Response = Block A Block*A B A*B;
test h=A e=Block*A;
run;
