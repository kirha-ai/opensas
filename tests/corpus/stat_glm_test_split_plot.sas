/* Complete middle GLM analysis of SAS/STAT15.4 Example84.1.
 * Public24-row input is shared with the MIXED regression.
 * TEST H/E contract: physical pp.4105–4106. */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

%include 'tests/fixtures/stat/mixed/split_plot.sas';
proc glm data=sp;
class A B Block;
model Y = A B A*B Block A*Block;
test h=A e=A*Block;
run;
