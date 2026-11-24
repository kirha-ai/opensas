/* STAT-STDRATE-006: STDRATE — Applicable Confidence Limits for Rate and Risk Statistics
 * Source: S154 / Chapter 116 / `Applicable Confidence Limits for Rate and Risk Statistics` (PDF pp. 9519–9520).
 * Discriminates: Example 116.2: Computing Mantel-Haenszel Risk Estimation
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data School;
input Smoking $ Pet $ Grade $ Case Student;
datalines;
Yes Yes K-1 109 807
Yes Yes 2-3 106 791
Yes Yes 4-5 112 868
Yes No K-1 168 1329
Yes No 2-3 162 1337
Yes No 4-5 183 1594
No Yes K-1 284 2403
No Yes 2-3 266 2237
No Yes 4-5 273 2279
No No K-1 414 3398
No No 2-3 372 3251
No No 4-5 382 3270
;
ods graphics on;
proc stdrate data=School
method=mh
stat=risk
effect=diff
plots=all
;
population group=Smoking event=Case total=Student;
strata Pet Grade / order=data stats(cl=none) effect;
run;
