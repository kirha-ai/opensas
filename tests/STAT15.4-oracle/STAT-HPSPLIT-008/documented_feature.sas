/* STAT-HPSPLIT-008: HPSPLIT — GROW / PARTITION / PRUNE
 * Source: S154 / Chapter 68 / `GROW Statement` (PDF pp. 5090–5092); S154 / Chapter 68 / `PARTITION Statement` (PDF pp. 5093–5095); S154 / Chapter 68 / `PRUNE Statement` (PDF pp. 5095–5096).
 * Discriminates: Example 68.5: Assessing Variable Importance; explicit statements: PRUNE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data MBE_Data;
label gTemp = 'Growth Temperature of Substrate';
label aTemp = 'Anneal Temperature';
label Rot = 'Rotation Speed';
label Dopant = 'Dopant Atom';
label Usable = 'Experiment Could Be Performed';
length Dopant $2 Usable $8;
input gTemp aTemp Rot Dopant $ Usable $;
datalines;
384.614 633.172 1.01933 C Unusable
363.874 512.942 0.72057 C Unusable
397.395 671.179 0.90419 C Unusable
389.962 653.940 1.01417 C Unusable
387.763 612.545 1.00417 C Unusable
394.206 617.021 1.07188 Si Usable
387.135 616.035 0.94740 Si Usable
428.783 745.345 0.99087 Si Unusable
399.365 600.932 1.23307 Si Unusable
455.502 648.821 1.01703 Si Unusable
387.362 697.589 1.01623 Ge Usable
408.872 640.406 0.94543 Ge Usable
407.734 628.196 1.05137 Ge Usable
417.343 612.328 1.03960 Ge Usable
482.539 669.392 0.84249 Ge Unusable
367.116 564.246 0.99642 Sn Unusable
398.594 733.839 1.08744 Sn Unusable
378.032 619.561 1.06137 Sn Usable
357.544 606.871 0.85205 Sn Unusable
384.578 635.858 1.12215 Sn Unusable
;
proc hpsplit data=MBE_Data maxdepth=6 seed=314159;
class Usable Dopant;
model Usable = gTemp aTemp Rot Dopant;
prune none;
run;
