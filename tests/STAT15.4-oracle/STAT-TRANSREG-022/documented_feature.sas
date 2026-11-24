/* STAT-TRANSREG-022: TRANSREG — Official examples and feature integration regression
 * Source: S154 / Chapter 126 / `Examples: TRANSREG Procedure` (PDF pp. 10528–10566).
 * Discriminates: Example 126.1: Transformation Regression of Exhaust Emissions Data
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
title 'Gasoline Example';
title2 'Iteratively Estimate NOx, CpRatio, EqRatio, and Fuel';
* Fit the Nonparametric Model;
proc transreg data=sashelp.Gas solve test nomiss plots=all;
ods exclude where=(_path_ ? 'MV');
model mspline(NOx / nknots=9) = spline(EqRatio / nknots=9)
monotone(CpRatio) opscore(Fuel);
run;
title2 'Now fit log(NOx) = b0 + b1*EqRatio + b2*EqRatio**2 +';
title3 'b3*CpRatio + Sum b(j)*Fuel(j) + Error';
*-Fit the Parametric Model Suggested by the Nonparametric Analysis-;
proc transreg data=sashelp.Gas solve ss2 short nomiss plots=all;
model log(NOx) = pspline(EqRatio / deg=2) identity(CpRatio)
opscore(Fuel);
run;
