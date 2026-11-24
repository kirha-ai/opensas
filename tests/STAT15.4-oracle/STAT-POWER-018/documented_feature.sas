/* STAT-POWER-018: POWER — Official examples and feature integration regression
 * Source: S154 / Chapter 96 / `Examples: POWER Procedure` (PDF pp. 7918–7984).
 * Discriminates: Example 96.9: Binary Logistic Regression with Independent Predictors
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc power;
logistic
vardist("Heat") = ordinal((5 10 15 20) : (0.2 0.3 0.3 0.2))
vardist("Soak") = ordinal((2 4 6) : (0.4 0.4 0.2))
vardist("Mass1") = normal(4, 1)
vardist("Mass2") = normal(4, 2)
testpredictor = "Heat"
covariates = "Soak" | "Mass1" "Mass2"
responseprob = 0.15 0.25
testoddsratio = 1.2
units= ("Heat" = 5)
covoddsratios = 1.4 | 1 1.3
alpha = 0.1
power = 0.9
ntotal = .;
run;
