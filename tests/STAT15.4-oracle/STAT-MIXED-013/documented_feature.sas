/* STAT-MIXED-013: MIXED — Residuals and Influence Diagnostics
 * Source: S154 / Chapter 84 / `Residuals and Influence Diagnostics` (PDF pp. 6712–6720).
 * Discriminates: Example 84.7: Influence in Heterogeneous Variance Model
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data absorb;
input FatType Absorbed @@;
datalines;
1 164 1 172 1 168 1 177 1 156 1 195
2 178 2 191 2 197 2 182 2 185 2 177
3 175 3 193 3 178 3 171 3 163 3 176
4 155 4 166 4 149 4 164 4 170 4 168
;
ods graphics on;
proc mixed data=absorb asycov;
class FatType;
model Absorbed = FatType / s
influence(iter=10 estimates);
repeated / group=FatType;
ods output Influence=inf;
run;
ods graphics off;
proc print data=inf label;
var parm1-parm5 covp1-covp4;
run;
proc print data=inf label;
var observed predicted residual pressres
student Rstudent;
run;
proc print data=inf label;
var leverage observed CookD DFFITS CovRatio RLD;
run;
proc print data=inf label;
var iter CookDCP CovRatioCP;
run;
