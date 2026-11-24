/* STAT-DATASET-004: Statistical data sets — TYPE=COV Data Sets / TYPE=CSSCP Data Sets / TYPE=DISTANCE Data Sets
 * Source: S154 / Special SAS Data Sets / `TYPE=COV Data Sets` (PDF p. 10888); S154 / Special SAS Data Sets / `TYPE=CSSCP Data Sets` (PDF p. 10888); S154 / Special SAS Data Sets / `TYPE=DISTANCE Data Sets` (PDF pp. 10888–10889); S154 / Special SAS Data Sets / `Definitional Formulas` (PDF pp. 10893–10894).
 * Discriminates: Native correlation/covariance/SSCP rows, reserved variables and data set metadata
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

%macro _oracle_descriptor(ds);
proc contents data=&ds out=_oracle_descriptor(keep=name type length varnum label format informat) noprint; run;
proc sort data=_oracle_descriptor; by varnum; run;
proc print data=_oracle_descriptor noobs; run;
data _oracle_member;
length Dataset $64 DatasetType $16;
Dataset="&ds"; _handle=open("&ds");
DatasetType=attrc(_handle,'TYPE'); NObs=attrn(_handle,'NOBS'); NVars=attrn(_handle,'NVARS');
_close=close(_handle); drop _handle _close;
run;
proc print data=_oracle_member noobs; run;
%mend;


data sample;
 input x z y group $ weight freq;
 datalines;
1 1 4 A 1 1
2 1 6 A 2 1
3 2 7 A 1 2
4 1 9 A 1 1
5 3 13 A 2 1
6 2 12 A 1 1
7 4 17 B 1 1
8 3 19 B 2 2
9 5 20 B 1 1
10 3 23 B 1 1
11 5 25 B 2 1
12 4 24 B 1 1
;
run;
proc corr data=sample outp=pearson cov csscp sscp; var x z y; run;
proc print data=pearson noobs; format _numeric_ best32.; run;
%_oracle_descriptor(pearson);
data sscp(type=sscp); set pearson; where _TYPE_='SSCP'; run;
proc print data=sscp noobs; run;
