/* expect-rc: 0
 * STAT-VARCLUS-001: PROC VARCLUS splitting criteria on SASHELP.IRIS (Fisher
 * 1936, public sample data): MAXEIGEN= alone (stops by the criterion after
 * two clusters; header Proportion 0), PROPORTION= and its alias PERCENT=
 * (values > 1 are percentages; header Maxeigen 0; "smallest proportion"
 * split message), MAXCLUSTERS=1 (no history table), MAXCLUSTERS= with
 * MAXEIGEN=, PROPORTION=1 (down to single-variable clusters, a tied
 * two-variable split, maximum second eigenvalue 0) and a repeated PROC
 * option (the last MAXCLUSTERS= is used). Expected listing: SAS 9.4 /
 * SAS/STAT 15.4 output of this exact program.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
ods graphics off;
proc varclus data=sashelp.iris maxeigen=0.5;
run;
proc varclus data=sashelp.iris proportion=0.95;
run;
proc varclus data=sashelp.iris percent=90;
run;
proc varclus data=sashelp.iris maxc=1;
run;
proc varclus data=sashelp.iris maxc=3 maxeigen=0.3;
run;
proc varclus data=sashelp.iris proportion=1;
run;
proc varclus data=sashelp.iris maxc=2 maxc=3;
run;
