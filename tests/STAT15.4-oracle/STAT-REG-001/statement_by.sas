/* STAT-REG-001: REG — Data input, variable roles, and basic options
 * Source: S154 / Chapter 105 / `PROC REG Statement` (PDF pp. 8560–8574); S154 / Chapter 105 / `BY Statement` (PDF pp. 8574–8575); S154 / Chapter 105 / `FREQ Statement` (PDF p. 8576); S154 / Chapter 105 / `ID Statement` (PDF p. 8576); S154 / Chapter 105 / `VAR Statement` (PDF pp. 8599–8600); S154 / Chapter 105 / `WEIGHT Statement` (PDF p. 8600); S154 / Chapter 105 / `Missing Values` (PDF p. 8600); S154 / Chapter 105 / `Input Data Sets` (PDF pp. 8600–8603).
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

data _oracle_input; set sashelp.class; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;


proc reg data=_oracle_input;
by _oracle_by;
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
