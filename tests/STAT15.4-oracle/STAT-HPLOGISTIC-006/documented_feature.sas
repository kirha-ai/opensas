/* STAT-HPLOGISTIC-006: HPLOGISTIC — PARTITION / SELECTION / Using Validation and Test Data
 * Source: S154 / Chapter 61 / `PARTITION Statement` (PDF p. 4762); S154 / Chapter 61 / `SELECTION Statement` (PDF pp. 4763–4764); S154 / Chapter 61 / `Using Validation and Test Data` (PDF pp. 4768–4770).
 * Discriminates: Example 61.4: Partitioning Data; explicit statements: PARTITION, SELECTION
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc hplogistic data=Sashelp.JunkMail;
model Class(event='1')=Make Address All _3d Our Over Remove Internet Order
Mail Receive Will People Report Addresses Free Business Email You
Credit Your Font _000 Money HP HPL George _650 Lab Labs Telnet _857
Data _415 _85 Technology _1999 Parts PM Direct CS Meeting Original
Project RE Edu Table Conference Semicolon Paren Bracket Exclamation
Dollar Pound CapAvg CapLong CapTotal;
partition rolevar=Test(train='0' test='1');
selection method=forward;
run;
proc hplogistic data=Sashelp.JunkMail;
model Class(event='1')= Our Over Remove Internet Order Will
Free Business You Your Font _000 Money HP George Parts
Meeting RE Edu Semicolon Exclamation Dollar CapAvg
CapLong;
partition fraction(test=0 validation=0);
run;
data JunkMail;
set Sashelp.JunkMail;
Role=0;
run;
proc hplogistic data=JunkMail;
model Class(event='1')= Our Over Remove Internet Order Will
Free Business You Your Font _000 Money HP George Parts
Meeting RE Edu Semicolon Exclamation Dollar CapAvg
CapLong;
partition role=Role(train='0');
run;
