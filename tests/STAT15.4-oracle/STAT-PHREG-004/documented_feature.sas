/* STAT-PHREG-004: PHREG — CLASS / EFFECT / MODEL
 * Source: S154 / Chapter 92 / `CLASS Statement` (PDF pp. 7355–7359); S154 / Chapter 92 / `EFFECT Statement` (PDF p. 7362); S154 / Chapter 92 / `MODEL Statement` (PDF pp. 7370–7380).
 * Discriminates: Example 92.15: Analysis of Competing-Risks Data; explicit statements: CLASS, MODEL
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc format; value DiseaseGroup 1='ALL' 2='AML-Low Risk' 3='AML-High Risk'; run;
data Bmt;
input Disease T Status @@;
label T='Disease-Free Survival in Days';
format Disease DiseaseGroup.;
datalines;
1 2081 0 1 1602 0 1 1496 0 1 1462 0 1 1433 0
1 1377 0 1 1330 0 1 996 0 1 226 0 1 1199 0
1 1111 0 1 530 0 1 1182 0 1 1167 0 1 418 2
1 383 1 1 276 2 1 104 1 1 609 1 1 172 2
1 487 2 1 662 1 1 194 2 1 230 1 1 526 2
1 122 2 1 129 1 1 74 1 1 122 1 1 86 2
1 466 2 1 192 1 1 109 1 1 55 1 1 1 2
1 107 2 1 110 1 1 332 2 2 2569 0 2 2506 0
2 2409 0 2 2218 0 2 1857 0 2 1829 0 2 1562 0
2 1470 0 2 1363 0 2 1030 0 2 860 0 2 1258 0
2 2246 0 2 1870 0 2 1799 0 2 1709 0 2 1674 0
2 1568 0 2 1527 0 2 1324 0 2 957 0 2 932 0
2 847 0 2 848 0 2 1850 0 2 1843 0 2 1535 0
2 1447 0 2 1384 0 2 414 2 2 2204 2 2 1063 2
2 481 2 2 105 2 2 641 2 2 390 2 2 288 2
2 421 1 2 79 2 2 748 1 2 486 1 2 48 2
2 272 1 2 1074 2 2 381 1 2 10 2 2 53 2
2 80 2 2 35 2 2 248 1 2 704 2 2 211 1
2 219 1 2 606 1 3 2640 0 3 2430 0 3 2252 0
3 2140 0 3 2133 0 3 1238 0 3 1631 0 3 2024 0
3 1345 0 3 1136 0 3 845 0 3 422 1 3 162 2
3 84 1 3 100 1 3 2 2 3 47 1 3 242 1
3 456 1 3 268 1 3 318 2 3 32 1 3 467 1
3 47 1 3 390 1 3 183 2 3 105 2 3 115 1
3 164 2 3 93 1 3 120 1 3 80 2 3 677 2
3 64 1 3 168 2 3 74 2 3 16 2 3 157 1
3 625 1 3 48 1 3 273 1 3 63 2 3 76 1
3 113 1 3 363 2
;
data Risk;
Disease=1;
output;
Disease=2;
output;
Disease=3;
output;
format Disease DiseaseGroup.;
run;
ods graphics on;
proc phreg data=Bmt plots(overlay=stratum)=cif;
class Disease (order=internal ref=first);
model T*Status(0)=Disease / eventcode=1;
Hazardratio 'Pairwise' Disease / diff=pairwise;
baseline covariates=Risk out=out1 cif=_all_ / seed=191;
run;
proc print data=Out1(where=(Disease=1));
title 'CIFs Estimates and 95% Confidence limits for the ALL Group';
run;
ods graphics on;
title 'Cause-specific Analysis';
proc phreg data=Bmt plots(overlay)=cif;
class Disease (order=internal ref=first);
model T*Status(0)=Disease / eventcode(cox)=1;
baseline covariates=Risk out=out2 cif=_all_;
run;
proc print data=Out2(where=(Disease=1));
title 'CIF Estimates and 95% Confidence limits for the ALL Group';
run;
