/* STAT-SURVEYIMPUTE-009: SURVEYIMPUTE — Official examples and feature integration regression
 * Source: S154 / Chapter 119 / `Examples: SURVEYIMPUTE Procedure` (PDF pp. 9767–9792).
 * Discriminates: Example 119.3: Fully Efficient Fractional Imputation, Fay's Balanced Repeated Replication, and Domain Analysis
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

/* Seeded synthetic survey input; not the externally distributed NHANES file. */
data Smoke;
call streaminit(314159);
array reps{4} wtpqrp1-wtpqrp4;
do seqn=1 to 512;
 HFA7=6+mod(seqn,12); DMARETHN=1+mod(floor((seqn-1)/2),4); HSSEX=1+mod(seqn,2);
 stratum=1+mod(floor((seqn-1)/8),2); psu=1+mod(floor((seqn-1)/16),2);
 wtpfqx6=1.5+mod(seqn,3)/2;
 HFF1MI=1+rand('bernoulli',0.45); HAN6SRMI=1+rand('bernoulli',0.55);
 HAR3RMI=1+rand('bernoulli',0.5); HAT28MI=1+rand('bernoulli',0.4);
 HFF1IF=1+rand('bernoulli',0.08); HAN6SRIF=1+rand('bernoulli',0.08);
 HAR3RIF=1+rand('bernoulli',0.08); HAT28IF=1+rand('bernoulli',0.08);
 do r=1 to 4;
  choice=1+mod(floor((r-1)/(2**(stratum-1))),2);
  if psu=choice then reps{r}=1.7*wtpfqx6; else reps{r}=0.3*wtpfqx6;
 end;
 output;
end;
drop r choice;
run;
data Smoke;
set Smoke;
if HFA7 <=8 then Education='Elementary ';
if HFA7 > 8 and HFA7 <= 12 then Education='High School';
if HFA7 > 12 and HFA7 <= 17 then Education='College ';
if HFA7 > 17 then Education='Unknown ';
if DMARETHN = 1 & HSSEX = 1 then ImputationCells=1;
if DMARETHN = 1 & HSSEX = 2 then ImputationCells=2;
if DMARETHN = 2 & HSSEX = 1 then ImputationCells=3;
if DMARETHN = 2 & HSSEX = 2 then ImputationCells=4;
if DMARETHN = 3 & HSSEX = 1 then ImputationCells=5;
if DMARETHN = 3 & HSSEX = 2 then ImputationCells=6;
if DMARETHN = 4 then ImputationCells=7;
if HFF1IF = 2 then HFF1MI = .;
if HAN6SRIF = 2 then HAN6SRMI = .;
if HAR3RIF = 2 then HAR3RMI = .;
if HAT28IF = 2 then HAT28MI = .;
run;
proc surveyimpute data=Smoke method=FEFI varmethod=BRR;
weight wtpfqx6;
repweights wtpqrp:;
id seqn;
class hff1mi han6srmi har3rmi hat28mi;
var hff1mi han6srmi har3rmi hat28mi;
cells ImputationCells;
output out=SmokeImputed;
run;
proc surveyfreq data=SmokeImputed varmethod=brr(fay=0.3) varheader=label;
weight ImpWt;
repweights ImpRepWt_:;
table HFF1MI*HAR3RMI;
table Education*HAT28MI / row nototal nofreq nowt;
run;
