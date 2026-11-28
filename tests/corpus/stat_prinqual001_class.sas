/* STAT-PRINQUAL-001: the reference program's PROC PRINQUAL step on the
   published SASHELP.CLASS sample (IDENTITY transformations of Height, Weight
   and Age; default METHOD=MTV, N=2). Expected listing: the SAS 9.4 reference
   output (Proportion of Variance 0.96325 = (2.62135 + 0.26839) / 3, the two
   largest eigenvalues of the correlation matrix). The reference's PROC PRINT
   of OUT= is left out: Base PROC PRINT decimal alignment is a known separate
   blocker; the OUT= values are covered by the src/stat/prinqual_tests.zig
   tests. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
proc prinqual data=sashelp.class out=scaled;
transform identity(height weight age);
run;
