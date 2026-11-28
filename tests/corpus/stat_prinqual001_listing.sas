/* STAT-PRINQUAL-001: PROC PRINQUAL iteration history for IDENTITY
   transformations (they cannot change, so the analysis converges at
   iteration 1). Expected listing: a SAS 9.4 run of these steps on the same
   data. Covers COVARIANCE with TSTANDARD=Z and REPLACE, an ID statement,
   TSTANDARD=CENTER with TPREFIX=, N= equal to the number of variables
   (Proportion of Variance 1), METHOD=MAC, the default DATAn output name and
   a passive observation (missing x). Data: invented. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data a;
input g id $ x y z f w;
datalines;
1 a 1 2 3 1 1
1 b 2 1 5 2 0.5
1 c 3 4 4 0.5 1
1 d 4 3 7 2.7 1
1 e . 5 1 1 1
1 k 5 6 6 1 0
2 f 5 5 2 1 1
2 h 6 7 9 1 1
2 i 7 6 4 1 2
2 j 8 9 8 1 1
;
proc prinqual data=a out=o2 cov tstandard=z replace;
transform identity(x y z);
id id g;
run;
proc prinqual data=a out=o3 tstandard=center tprefix=Q_;
transform identity(x y z);
run;
proc prinqual data=a n=3;
transform identity(x y z);
run;
proc prinqual data=a out=o6 method=mac;
transform identity(x y z);
run;
