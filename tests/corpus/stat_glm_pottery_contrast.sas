/* Permanent univariate Al contrast from S154 Example53.6.
 * Exact formatted input is shared; this does not claim MANOVA support. */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title "Romano-British Pottery";
%include 'tests/fixtures/stat/glm/pottery_formatted.sas';
proc glm data=pottery;
class Site;
model Al=Site;
contrast 'Llanederyn vs. the rest' Site 1 1 1 -3;
run;
