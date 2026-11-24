/* STAT-INBREED-005: INBREED — OUTCOV= Data Set
 * Source: S154 / Chapter 71 / `OUTCOV= Data Set` (PDF pp. 5285–5287).
 * Discriminates: Getting Started: INBREED Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Population;
input Individual $ Parent1 $ Parent2 $
Covariance Sex $ Generation;
datalines;
Mark George Lisa . M 1
Kelly Scott Lisa . F 1
Mike George Amy . M 1
. Mark Kelly 0.50 . 1
David Mark Kelly . M 2
Merle Mike Jane . F 2
Jim Mark Kelly 0.50 M 2
Mark Mike Kelly . M 2
;
proc inbreed data=Population covar matrix init=0.25;
run;
proc inbreed data=Population covar matrix init=0.25;
class Generation;
run;
proc inbreed data=Population covar average init=0.25;
class Generation;
gender Sex;
run;
