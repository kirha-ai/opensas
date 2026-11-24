/* STAT-DATASET-002: Statistical data sets — TYPE=ACE Data Sets / TYPE=BOXPLOT Data Sets / TYPE=CALISFIT Data Sets
 * Source: S154 / Special SAS Data Sets / `TYPE=ACE Data Sets` (PDF p. 10883); S154 / Special SAS Data Sets / `TYPE=BOXPLOT Data Sets` (PDF p. 10883); S154 / Special SAS Data Sets / `TYPE=CALISFIT Data Sets` (PDF pp. 10883–10884); S154 / Special SAS Data Sets / `Definitional Formulas` (PDF pp. 10893–10894).
 * Discriminates: Native TYPE=ACE output and its descriptor
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


proc aceclus data=sashelp.iris outstat=structure p=0.1; var SepalLength SepalWidth PetalLength PetalWidth; run; %_oracle_descriptor(structure); proc print data=structure noobs; run;
