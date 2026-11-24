/* STAT-STDRATE-005: STDRATE — Attributable Fraction and Population Attributable Fraction / Applicable Data Sets and Required Variables for Method Specifications
 * Source: S154 / Chapter 116 / `Attributable Fraction and Population Attributable Fraction` (PDF pp. 9514–9518); S154 / Chapter 116 / `Applicable Data Sets and Required Variables for Method Specifications` (PDF pp. 9518–9519).
 * Discriminates: Example 116.3: Computing Attributable Fraction Estimates
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Factory;
input Age $ Event_E Count_E Event_NE Count_NE;
datalines;
20-29 31 352 143 2626
30-39 57 486 392 4124
40-49 62 538 459 4662
50-59 50 455 337 3622
60-69 38 322 199 2155
70+ 9 68 35 414
;
ods graphics on;
proc stdrate data=Factory
refdata=Factory
method=indirect(af)
stat=risk
plots(stratum=horizontal)
;
population event=Event_E total=Count_E;
reference event=Event_NE total=Count_NE;
strata Age / stats;
run;
data Factory1;
input Exposure $ Age $ Event Count;
datalines;
Yes 20-29 31 352
Yes 30-39 57 486
Yes 40-49 62 538
Yes 50-59 50 455
Yes 60-69 38 322
Yes 70+ 9 68
No 20-29 143 2626
No 30-39 392 4124
No 40-49 459 4662
No 50-59 337 3622
No 60-69 199 2155
No 70+ 35 414
;
proc stdrate data=Factory1
method=mh(af)
stat=risk
effect
;
population group(order=data exposed='Yes')=Exposure
event=Event total=Count;
strata Age;
run;
