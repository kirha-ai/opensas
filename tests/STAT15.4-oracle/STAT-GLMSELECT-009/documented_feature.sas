/* STAT-GLMSELECT-009: GLMSELECT — Elastic Net Selection (ELASTICNET) / Group LASSO Selection (GROUPLASSO) / Model Selection Issues
 * Source: S154 / Chapter 56 / `Elastic Net Selection (ELASTICNET)` (PDF pp. 4364–4366); S154 / Chapter 56 / `Group LASSO Selection (GROUPLASSO)` (PDF pp. 4366–4367); S154 / Chapter 56 / `Model Selection Issues` (PDF pp. 4367–4368).
 * Discriminates: Example 56.6: Elastic Net and External Cross Validation
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
proc glmselect data=sashelp.Leutrain valdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=LASSO(steps=120 choose=validate);
run;
proc glmselect data=sashelp.Leutrain valdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=elasticnet(steps=120 L2=0.001 choose=validate);
run;
proc glmselect data=sashelp.Leutrain valdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=elasticnet(steps=120 choose=validate);
run;
proc glmselect data=sashelp.Leutrain testdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=elasticnet(steps=120 choose=cv)cvmethod=split(4);
run;
proc glmselect data=sashelp.Leutrain testdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=elasticnet(steps=120 choose=cvex)cvmethod=split(4);
run;
