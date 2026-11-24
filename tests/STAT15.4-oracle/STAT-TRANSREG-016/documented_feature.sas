/* STAT-TRANSREG-016: TRANSREG — Hypothesis Tests with One-Way ANOVA
 * Source: S154 / Chapter 126 / `Hypothesis Tests with One-Way ANOVA` (PDF pp. 10512–10515).
 * Discriminates: Getting Started: TRANSREG Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Gasoline and Emissions Data';
data gas;
set sashelp.gas;
if fuel in ('Ethanol', '82rongas', 'Gasohol');
run;
ods graphics on;
* Request a Spline Transformation of Equivalence Ratio;
proc transreg data=Gas solve ss2 plots=(transformation obp residuals);
model identity(nox) = spline(EqRatio / nknots=4);
run;
* Separate Curves and Intercepts;
proc transreg data=Gas solve ss2 additive plots=(transformation obp);
model identity(nox) = class(Fuel / zero=none) |
spline(EqRatio / nknots=4 after);
run;
* Separate Intercepts;
proc transreg data=Gas solve ss2 additive;
model identity(nox) = class(Fuel / zero=none)
spline(EqRatio / nknots=4);
run;
* Separate Curves and Intercepts with Penalized B-Splines;
proc transreg data=Gas ss2 plots=transformation lprefix=0;
model identity(nox) = class(Fuel / zero=none) * pbspline(EqRatio);
run;
title 'Introductory Main-Effects ANOVA Example';
data a;
input y x1 $ x2 $;
datalines;
8 a a
7 a a
4 a b
3 a b
5 b a
4 b a
2 b b
1 b b
8 c a
7 c a
5 c b
2 c b
;
* Fit a main-effects ANOVA model with 1, 0, -1 coding;
proc transreg ss2;
model identity(y) = class(x1 x2 / effects);
output coefficients replace;
run;
* Display TRANSREG output data set;
proc print label;
format intercept -- x2a 5.2;
run;
