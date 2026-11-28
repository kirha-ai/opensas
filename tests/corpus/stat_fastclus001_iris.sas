/* STAT-FASTCLUS-001: PROC FASTCLUS default least-squares listing on the
 * published SASHELP.IRIS sample (MAXCLUSTERS=3 MAXITER=50, VAR role, OUT=).
 * Expected listing: the SAS 9.4 reference listing of this same step
 * (STAT-FASTCLUS-001 oracle case documented_feature, FASTCLUS part only).
 * Blank lines between steps and at the end follow the opensas listing
 * convention (every other line and token is the SAS text).
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc fastclus data=sashelp.iris maxclusters=3 maxiter=50 out=clusters;
var SepalLength SepalWidth PetalLength PetalWidth;
run;
