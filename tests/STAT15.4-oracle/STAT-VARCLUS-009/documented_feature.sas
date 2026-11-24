/* STAT-VARCLUS-009: VARCLUS — Official examples and feature integration regression
 * Source: S154 / Chapter 129 / `Getting Started: VARCLUS Procedure` (PDF pp. 10696–10699); S154 / Chapter 129 / `Overview: VARCLUS Procedure` (PDF pp. 10694–10696).
 * Discriminates: Example 129.1: Correlations among Physical Variables
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data phys8(type=corr);
length _name_ $32 _type_ $8;
infile datalines truncover;

title 'Eight Physical Measurements on 305 School Girls';
title2 'Harman: Modern Factor Analysis, 3rd Ed, p22';
label ArmSpan='Arm Span' Forearm='Length of Forearm'
LowerLeg='Length of Lower Leg' BitDiam='Bitrochanteric Diameter'
Girth='Chest Girth' Width='Chest Width';
input _Name_ :$32. Height ArmSpan Forearm LowerLeg Weight BitDiam Girth Width;
_Type_='corr';
datalines;
Height   1.0 .846 .805 .859 .473 .398 .301 .382
ArmSpan .846 1.0 .881 .826 .376 .326 .277 .415
Forearm .805 .881 1.0 .801 .380 .319 .237 .345
LowerLeg .859 .826 .801 1.0 .436 .329 .327 .365
Weight .473 .376 .380 .436 1.0 .762 .730 .629
BitDiam .398 .326 .319 .329 .762 1.0 .583 .577
Girth .301 .277 .237 .327 .730 .583 1.0 .539
Width .382 .415 .345 .365 .629 .577 .539 1.0
;
proc varclus data=phys8;
run;
