/* STAT-REG-014: REG — CODE / Predicted and Residual Values
 * Source: S154 / Chapter 105 / `CODE Statement` (PDF p. 8575); S154 / Chapter 105 / `Predicted and Residual Values` (PDF pp. 8619–8623).
 * Discriminates: Generate DATA step scoring code, execute it against the input rows, and print the scored data.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

filename _orcode "%sysfunc(pathname(work))/_oracle_score.sas";


proc reg data=sashelp.class;
model Weight = Height;

code file="%sysfunc(pathname(work))/_oracle_score.sas";
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

data _oracle_scored; set sashelp.class;
%include _orcode;
run;
proc print data=_oracle_scored(obs=10); run;
