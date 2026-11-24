/* STAT-NLIN-012: NLIN — OUTPUT / Output Data Sets
 * Source: S154 / Chapter 88 / `OUTPUT Statement` (PDF pp. 7004–7008); S154 / Chapter 88 / `Output Data Sets` (PDF pp. 7033–7034).
 * Discriminates: Example 88.2: Iteratively Reweighted Least Squares; explicit statements: OUTPUT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data uspop;
input pop :6.3 @@;
retain year 1780;
year = year+10;
yearsq = year*year;
datalines;
3929 5308 7239 9638 12866 17069 23191 31443 39818 50155
62947 75994 91972 105710 122775 131669 151325 179323 203211
226542 248710
;
title 'Beaton/Tukey Biweight Robust Regression using IRLS';
proc nlin data=uspop nohalve;
parms b0=20450.43 b1=-22.7806 b2=.0063456;
model pop=b0+b1*year+b2*year*year;
resid = pop-model.pop;
sigma = 2;
k = 4.685;
if abs(resid/sigma)<=k then _weight_=(1-(resid / (sigma*k))**2)**2;
else _weight_=0;
output out=c r=rbi;
run;
proc robustreg data=uspop method=m(scale=2);
model pop = year year*year;
output out=weights weight=w;
run;
proc print data=weights;
run;
