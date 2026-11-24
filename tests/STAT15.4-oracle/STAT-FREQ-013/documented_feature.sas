/* STAT-FREQ-013: FREQ — Jonckheere-Terpstra Test
 * Source: S154 / Chapter 47 / `Jonckheere-Terpstra Test` (PDF pp. 3214–3216).
 * Discriminates: Getting Started: FREQ Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data SummerSchool;
input Gender $ Internship $ Enrollment $ Count @@;
datalines;
boys yes yes 35 boys yes no 29
boys no yes 14 boys no no 27
girls yes yes 32 girls yes no 10
girls no yes 53 girls no no 23
;
proc freq data=SummerSchool order=data;
tables Internship*Enrollment / chisq;
weight Count;
run;
ods graphics on;
proc freq data=SummerSchool;
tables Gender*Internship*Enrollment /
chisq cmh plots(only)=freqplot(twoway=cluster);
weight Count;
run;
ods graphics off;
data SkinCondition;
input Derm1 $ Derm2 $ Count;
datalines;
terrible terrible 10
terrible poor 4
terrible marginal 1
terrible clear 0
poor terrible 5
poor poor 10
poor marginal 12
poor clear 2
marginal terrible 2
marginal poor 4
marginal marginal 12
marginal clear 5
clear terrible 0
clear poor 2
clear marginal 6
clear clear 13
;
ods graphics on;
proc freq data=SkinCondition order=data;
tables Derm1*Derm2 /
agree noprint plots=agreeplot;
test kappa;
weight Count;
run;
ods graphics off;
run;
quit;
