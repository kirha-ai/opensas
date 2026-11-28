/* STAT-REG-019: REG Computer Resources (S154 p. 8650) — the reference case
 * Example 105.4 (published insurance data): a fit, an interactive DELETE and
 * PRINT refit give the reference listing. Deviations from the original
 * program, each an owned gap: TITLE omitted (opensas does not repeat the
 * title on REG continuation pages), OUTPUT after the DELETE (STAT-REG-016)
 * and PROC SGPLOT (not implemented) dropped. Expected words are the SAS 9.4
 * reference listing without its two title lines.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
ods graphics off;
data insurance;
input time size type @@;
sizetype=size*type;
datalines;
17 151 0 26 92 0 21 175 0 30 31 0 22 104 0 0 277 0 12 210 0
19 120 0 4 290 0 16 238 0 28 164 1 15 272 1 11 295 1 38 68 1
31 85 1 21 224 1 20 166 1 13 305 1 30 124 1 14 246 1
;
proc reg data=insurance;
model time = size type sizetype;
run;
delete sizetype;
print;
run;
quit;
