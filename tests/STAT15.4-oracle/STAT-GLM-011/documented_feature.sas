/* STAT-GLM-011: GLM — CONTRAST / ESTIMATE / MANOVA
 * Source: S154 / Chapter 53 / `CONTRAST Statement` (PDF pp. 4068–4070); S154 / Chapter 53 / `ESTIMATE Statement` (PDF pp. 4070–4071); S154 / Chapter 53 / `MANOVA Statement` (PDF pp. 4081–4086).
 * Discriminates: Example 53.6: Multivariate Analysis of Variance; explicit statements: CONTRAST, MANOVA
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title "Romano-British Pottery";
data pottery;
input Site $12. Al Fe Mg Ca Na;
datalines;
Llanederyn 14.4 7.00 4.30 0.15 0.51
Llanederyn 13.8 7.08 3.43 0.12 0.17
Llanederyn 14.6 7.09 3.88 0.13 0.20
Llanederyn 11.5 6.37 5.64 0.16 0.14
Llanederyn 13.8 7.06 5.34 0.20 0.20
Llanederyn 10.9 6.26 3.47 0.17 0.22
Llanederyn 10.1 4.26 4.26 0.20 0.18
Llanederyn 11.6 5.78 5.91 0.18 0.16
Llanederyn 11.1 5.49 4.52 0.29 0.30
Llanederyn 13.4 6.92 7.23 0.28 0.20
Llanederyn 12.4 6.13 5.69 0.22 0.54
Llanederyn 13.1 6.64 5.51 0.31 0.24
Llanederyn 12.7 6.69 4.45 0.20 0.22
Llanederyn 12.5 6.44 3.94 0.22 0.23
Caldicot 11.8 5.44 3.94 0.30 0.04
Caldicot 11.6 5.39 3.77 0.29 0.06
IslandThorns 18.3 1.28 0.67 0.03 0.03
IslandThorns 15.8 2.39 0.63 0.01 0.04
IslandThorns 18.0 1.50 0.67 0.01 0.06
IslandThorns 18.0 1.88 0.68 0.01 0.04
IslandThorns 20.8 1.51 0.72 0.07 0.10
AshleyRails 17.7 1.12 0.56 0.06 0.06
AshleyRails 18.3 1.14 0.67 0.06 0.05
AshleyRails 16.7 0.92 0.53 0.01 0.05
AshleyRails 14.8 2.74 0.67 0.03 0.05
AshleyRails 19.1 1.64 0.60 0.10 0.03
;
proc glm data=pottery;
class Site;
model Al Fe Mg Ca Na = Site;
contrast 'Llanederyn vs. the rest' Site 1 1 1 -3;
manova h=_all_ / printe printh;
run;
