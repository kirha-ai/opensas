/* STAT-SASHELP-006: the built-in SASHELP.MILEAGES feeds PROC CLUSTER as a
 * TYPE=DISTANCE data set (the member itself has no TYPE attribute, so the
 * data set option is required, as in the SAS/STAT documentation example).
 * Expected listing: the METHOD=AVERAGE PSEUDO section of the SAS 9.4M9
 * reference for the CLUSTER documentation example (ODS GRAPHICS does not
 * change this table; the dendrogram is owned by STAT-CLUSTER-008). */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
title 'Cluster Analysis of Flying Mileages Between 10 American Cities';
title2 'Using METHOD=AVERAGE';
proc cluster data=sashelp.mileages(type=distance) method=average pseudo;
id City;
run;
