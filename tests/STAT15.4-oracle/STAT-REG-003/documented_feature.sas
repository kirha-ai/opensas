/* STAT-REG-003: REG — MODEL
 * Source: S154 / Chapter 105 / `MODEL Statement` (PDF pp. 8576–8588).
 * Discriminates: Getting Started: REG Procedure; explicit statements: MODEL
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc reg data=sashelp.class;
model Weight = Height;
run;
data USPopulation;
input Population @@;
retain Year 1780;
Year = Year+10;
YearSq = Year *Year;
Population = Population/1000;
datalines;
3929 5308 7239 9638 12866 17069 23191 31443 39818 50155
62947 75994 91972 105710 122775 131669 151325 179323 203211
226542 248710 281422
;
proc reg data=USPopulation plots=ResidualByPredicted;
var YearSq;
model Population=Year / r clm cli;
run;
add YearSq;
print;
run;
proc reg data=USPopulation plots=predictions(X=Year);
model Population=Year Yearsq;
quit;
ods graphics off;
quit;
