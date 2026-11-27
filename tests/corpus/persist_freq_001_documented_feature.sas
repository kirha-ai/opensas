/* STAT-FREQ-001: FREQ — Data input, variable roles, and basic options
 * Source: S154 / Chapter 47 / `PROC FREQ Statement` (PDF pp. 3082–3084); S154 / Chapter 47 / `BY Statement` (PDF pp. 3084–3085); S154 / Chapter 47 / `WEIGHT Statement` (PDF pp. 3157–3158); S154 / Chapter 47 / `Inputting Frequency Counts` (PDF pp. 3158–3159); S154 / Chapter 47 / `Grouping with Formats` (PDF pp. 3159–3160); S154 / Chapter 47 / `Missing Values` (PDF pp. 3160–3162).
 * Discriminates: Verified default procedure context; explicit statements: WEIGHT
 * Shared original case: STAT-FREQ-001/003/006/008 documented_feature and
 * STAT-FREQ-002 documented_default. Executable bodies and full expected
 * outputs are identical except FREQ002's final RUN/QUIT whitespace.
 * Additional provenance: Chapter 47 Getting Started pp. 3072-3081 (002),
 * TABLES pp. 3106-3154 (003), Measures of Association pp. 3170-3180 (006),
 * Sensitivity and Specificity p. 3188 (008). Their independent numerical
 * checks remain in freq_persistence_tests.zig; this shared published example
 * alone does not exercise every option in those ticket families.
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
