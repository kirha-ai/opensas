/* STAT-VARIOGRAM-016: VARIOGRAM — The Moran Scatter Plot / ODS Graphics
 * Source: S154 / Chapter 131 / `The Moran Scatter Plot` (PDF pp. 10830–10832); S154 / Chapter 131 / `ODS Graphics` (PDF pp. 10838–10839).
 * Discriminates: Getting Started: VARIOGRAM Procedure
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
ods trace on;
ods trace on;
title 'Spatial Correlation Analysis with PROC VARIOGRAM';
ods graphics on;
proc variogram data=sashelp.thick plots=pairs(thr=30);
compute novariogram nhc=20;
coordinates xc=East yc=North;
var Thick;
run;
proc variogram data=sashelp.thick outv=outv;
compute lagd=7 maxlag=10 cl robust;
coordinates xc=East yc=North;
var Thick;
run;
proc variogram data=sashelp.thick outv=outv plots(only)=moran;
compute lagd=7 maxlag=10 autocorr(assum=random);
coordinates xc=East yc=North;
var Thick;
run;
proc variogram data=sashelp.thick outv=outv;
store out=SemivStoreGau / label='Thickness Gaussian WLS Fit';
compute lagd=7 maxlag=10;
coordinates xc=East yc=North;
model form=gau cl / covb;
var Thick;
run;
ods graphics off;
run;
quit;
ods trace off;
ods trace off;
ods graphics off;
