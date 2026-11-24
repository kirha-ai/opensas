/* STAT-QUANTREG-004: QUANTREG — CONDDIST / Quantile Regression as an Optimization Problem / Optimization Algorithms
 * Source: S154 / Chapter 103 / `CONDDIST Statement` (PDF pp. 8379–8384); S154 / Chapter 103 / `Quantile Regression as an Optimization Problem` (PDF pp. 8393–8394); S154 / Chapter 103 / `Optimization Algorithms` (PDF pp. 8394–8402).
 * Discriminates: Example 103.3: Quantile Regression Analysis of Birth-Weight Data
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc contents varnum data=sashelp.bweight;
ods select position;
run;
proc format;
value vfmt 0 = 'No Visit' 1 = 'Second Trimester'
2 = 'Last Trimester' 3 = 'First Trimester';
value efmt 0 = 'High School' 1 = 'Some College'
2 = 'College' 3 = 'Less Than High School';
run;
ods graphics on;
proc quantreg ci=sparsity/iid algorithm=interior(tolerance=5.e-4)
data=sashelp.bweight order=internal;
class Visit MomEdLevel;
model Weight = Black Married Boy Visit MomEdLevel MomSmoke
CigsPerDay MomAge MomAge*MomAge
MomWtGain MomWtGain*MomWtGain /
quantile= 0.05 to 0.95 by 0.05
plot=quantplot seed=314159;
format Visit vfmt. MomEdLevel efmt.;
run;
