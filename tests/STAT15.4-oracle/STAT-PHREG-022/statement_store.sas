/* STAT-PHREG-022: PHREG — STORE
 * Source: S154 / Chapter 92 / `STORE Statement` (PDF p. 7389).
 * Discriminates: Save the fitted item store and inspect it through PROC PLM SHOW ALL.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Rats;
label Days ='Days from Exposure to Death';
input Days Status Group @@;
datalines;
143 1 0 164 1 0 188 1 0 188 1 0
190 1 0 192 1 0 206 1 0 209 1 0
213 1 0 216 1 0 220 1 0 227 1 0
230 1 0 234 1 0 246 1 0 265 1 0
304 1 0 216 0 0 244 0 0 142 1 1
156 1 1 163 1 1 198 1 1 205 1 1
232 1 1 232 1 1 233 1 1 233 1 1
233 1 1 233 1 1 239 1 1 240 1 1
261 1 1 280 1 1 280 1 1 296 1 1
296 1 1 323 1 1 204 0 1 344 0 1
;
data Regimes;
Group=0;
output;
Group=1;
output;
run;
ods graphics on;
proc phreg data=Rats plot(overlay)=survival;
model Days*Status(0)=Group;
baseline covariates=regimes out=_null_;

store out=work._oracle_store;
run;
proc phreg data=Rats;
model Days*Status(0)=Group X;
X=Group*(log(Days) - 5.4);
run;
ods graphics on;
proc phreg data=Rats;
model Days*Status(0)=Group;
bayes seed=1 outpost=Post nmc=1000 nbi=200;
run;
data New;
set Post;
Indicator=(Group < 0);
label Indicator='Group < 0';
run;
proc means data=New(keep=Indicator) n mean;
run;

proc plm restore=work._oracle_store; show all; run;
