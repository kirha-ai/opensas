/* STAT-NPAR1WAY-002: NPAR1WAY — Nonparametric location and distribution comparisons for independent samples
 * Source: S154 / Chapter 90 / `Getting Started: NPAR1WAY Procedure` (PDF pp. 7206–7215); S154 / Chapter 90 / `Overview: NPAR1WAY Procedure` (PDF p. 7206).
 * Discriminates: Getting Started: NPAR1WAY Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Gossypol;
input Dose n;
do i=1 to n;
input Gain @@;
output;
end;
datalines;
0 16
228 229 218 216 224 208 235 229 233 219 224 220 232 200 208 232
.04 11
186 229 220 208 228 198 222 273 216 198 213
.07 12
179 193 183 180 143 204 114 188 178 134 208 196
.10 17
130 87 135 116 118 165 151 59 126 64 78 94 150 160 122 110 178
.13 11
154 130 130 118 118 104 112 134 98 100 104
;
proc npar1way data=Gossypol;
class Dose;
var Gain;
run;
ods graphics on;
proc npar1way data=Gossypol plots(only)=wilcoxonboxplot;
class Dose;
var Gain;
run;
ods graphics off;
proc npar1way data=Gossypol;
where Dose <= .04;
class Dose;
var Gain;
run;
