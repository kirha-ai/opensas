/* STAT-MIANALYZE-004: MIANALYZE — Multiple Imputation Efficiency / Multivariate Inferences / Examples of the Complete-Data Inferences
 * Source: S154 / Chapter 83 / `Multiple Imputation Efficiency` (PDF pp. 6572–6573); S154 / Chapter 83 / `Multivariate Inferences` (PDF pp. 6573–6574); S154 / Chapter 83 / `Examples of the Complete-Data Inferences` (PDF pp. 6575–6576).
 * Discriminates: Getting Started: MIANALYZE Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

*----------------- Data on Physical Fitness -----------------*
| These measurements were made on men involved in a physical |
| fitness course at N.C. State University. |
| Only selected variables of |
| Oxygen (oxygen intake, ml per kg body weight per minute), |
| Runtime (time to run 1.5 miles in minutes), and |
| RunPulse (heart rate while running) are used. |
| Certain values were changed to missing for the analysis. |
*------------------------------------------------------------*;
data Fitness1;
input Oxygen RunTime RunPulse @@;
datalines;
44.609 11.37 178 45.313 10.07 185
54.297 8.65 156 59.571 . .
49.874 9.22 . 44.811 11.63 176
. 11.95 176 . 10.85 .
39.442 13.08 174 60.055 8.63 170
50.541 . . 37.388 14.03 186
44.754 11.12 176 47.273 . .
51.855 10.33 166 49.156 8.95 180
40.836 10.95 168 46.672 10.00 .
46.774 10.25 . 50.388 10.08 168
39.407 12.63 174 46.080 11.17 156
45.441 9.63 164 . 8.92 .
45.118 11.08 . 39.203 12.88 168
45.790 10.47 186 50.545 9.93 148
48.673 9.40 186 47.920 11.50 170
47.467 10.50 170
;
proc mi data=Fitness1 seed=3237851 noprint out=outmi;
var Oxygen RunTime RunPulse;
run;
proc reg data=outmi outest=outreg covout noprint;
model Oxygen= RunTime RunPulse;
by _Imputation_;
run;
proc print data=outreg(obs=8);
var _Imputation_ _Type_ _Name_
Intercept RunTime RunPulse;
title 'Parameter Estimates from Imputed Data Sets';
run;
proc mianalyze data=outreg;
modeleffects Intercept RunTime RunPulse;
run;
