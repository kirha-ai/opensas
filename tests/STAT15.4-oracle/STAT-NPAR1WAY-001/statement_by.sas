/* STAT-NPAR1WAY-001: NPAR1WAY — Data input, variable roles, and basic options
 * Source: S154 / Chapter 90 / `PROC NPAR1WAY Statement` (PDF pp. 7215–7224); S154 / Chapter 90 / `BY Statement` (PDF p. 7224); S154 / Chapter 90 / `CLASS Statement` (PDF pp. 7224–7225); S154 / Chapter 90 / `FREQ Statement` (PDF pp. 7229–7230); S154 / Chapter 90 / `STRATA Statement` (PDF pp. 7233–7235); S154 / Chapter 90 / `VAR Statement` (PDF p. 7235); S154 / Chapter 90 / `Missing Values` (PDF pp. 7235–7236).
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
data _oracle_input; set Gossypol; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc npar1way data=_oracle_input;
by _oracle_by;
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
