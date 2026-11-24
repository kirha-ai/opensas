/* STAT-CATMOD-004: CATMOD — MODEL / RESPONSE / Specification of Effects
 * Source: S154 / Chapter 36 / `MODEL Statement` (PDF pp. 2201–2208); S154 / Chapter 36 / `RESPONSE Statement` (PDF pp. 2212–2219); S154 / Chapter 36 / `Specification of Effects` (PDF pp. 2224–2226).
 * Discriminates: Example 36.1: Linear Response Function, r=2 Responses; explicit statements: MODEL, RESPONSE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data detergent;
input Softness $ Brand $ Previous $ Temperature $ Count @@;
datalines;
soft X yes high 19 soft X yes low 57
soft X no high 29 soft X no low 63
soft M yes high 29 soft M yes low 49
soft M no high 27 soft M no low 53
med X yes high 23 med X yes low 47
med X no high 33 med X no low 66
med M yes high 47 med M yes low 55
med M no high 23 med M no low 50
hard X yes high 24 hard X yes low 37
hard X no high 42 hard X no low 68
hard M yes high 43 hard M yes low 52
hard M no high 30 hard M no low 42
;
title 'Detergent Preference Study';
proc catmod data=detergent;
response 1 0;
weight Count;
model Brand=Softness|Previous|Temperature / freq prob;
title2 'Saturated Model';
run;
model Brand=Softness Previous Temperature
/ clparm noprofile design;
title2 'Main-Effects Model';
run;
quit;
