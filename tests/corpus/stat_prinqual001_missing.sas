/* STAT-PRINQUAL-001: an empty input data set (a note, no listing, an empty
   OUT= data set), N= above the number of variables (warning, N=3 assumed,
   Proportion of Variance 1) and NOMISS with a formatted numeric ID and two
   observations with a missing IDENTITY value. Expected listing: a SAS 9.4 run
   of these steps on the same data. Data: invented. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data a;
input g num x y z;
format num z5.1;
datalines;
1 1 1 2 3
1 2 2 1 5
1 3 3 4 4
2 4 . 5 1
2 5 . 6 6
3 6 5 5 2
3 7 6 7 9
3 8 7 6 4
3 9 8 9 8
;
data e; set a; stop; run;
proc prinqual data=e out=oe;
transform identity(x y);
run;
proc prinqual data=a out=on n=5;
transform identity(x y z);
run;
proc prinqual data=a out=oid nomiss;
transform identity(x y z);
id num;
run;
