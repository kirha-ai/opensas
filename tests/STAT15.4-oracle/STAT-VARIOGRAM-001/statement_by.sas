/* STAT-VARIOGRAM-001: VARIOGRAM — Data input, variable roles, and basic options
 * Source: S154 / Chapter 131 / `PROC VARIOGRAM Statement` (PDF pp. 10768–10775); S154 / Chapter 131 / `BY Statement` (PDF pp. 10775–10776); S154 / Chapter 131 / `ID Statement` (PDF p. 10782); S154 / Chapter 131 / `VAR Statement` (PDF pp. 10799–10800).
 * Discriminates: Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Spatial Correlation Analysis with PROC VARIOGRAM';
ods graphics on;
data _oracle_input; set sashelp.thick; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc variogram data=_oracle_input plots=pairs(thr=30);
by _oracle_by;
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

run; quit;
