/* STAT-PRINQUAL-001: the unchanged reference program's steps on the
   published SASHELP.CLASS sample (IDENTITY transformations of Height, Weight
   and Age; default METHOD=MTV, N=2), including its PROC PRINT of OUT=.
   Expected listing: the SAS 9.4 reference output (Proportion of Variance
   0.96325 = (2.62135 + 0.26839) / 3, the two largest eigenvalues of the
   correlation matrix). The PRINQUAL section is byte-identical to SAS; the
   PROC PRINT section has SAS's tokens in order (76/76 overall) with the
   opensas PRINT column gutter (Base PRINT spacing, STAT-PRINT-001 scope). */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
proc prinqual data=sashelp.class out=scaled;
transform identity(height weight age);
run;
proc print data=scaled(obs=5) noobs;
run;
