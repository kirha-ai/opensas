/* Locks verified-correct SAS 9.4 MERGE edges (doc-finder tick213):
   (1) BY DESCENDING match-merge order + alignment;
   (2) mixed ascending/descending multi-key BY;
   (3) many-to-many is NOT cartesian: parallel read, hold-last of the
       shorter source within the BY group (the classic MERGE-vs-SQL surprise);
   (4) one-to-many: the ONE side holds its value across the MANY rows. */
data a; input k x; datalines;
3 30
2 20
1 10
;
run;
data b; input k y; datalines;
3 300
2 200
;
run;
data _null_;
  merge a b;
  by descending k;
  put "desc k=" k " x=" x " y=" y;
run;
data m; input g k x; datalines;
1 2 12
1 1 11
2 1 21
;
run;
data n; input g k y; datalines;
1 2 102
1 1 101
2 1 201
;
run;
data _null_;
  merge m n;
  by g descending k;
  put "multi g=" g " k=" k " x=" x " y=" y;
run;
data mm; input k x; datalines;
1 10
1 11
;
run;
data nn; input k y; datalines;
1 100
1 200
1 300
;
run;
data _null_;
  merge mm nn;
  by k;
  put "m2m k=" k " x=" x " y=" y;
run;
data one; input k x; datalines;
1 10
2 20
;
run;
data many; input k y; datalines;
1 100
1 200
1 300
3 400
;
run;
data _null_;
  merge one many;
  by k;
  put "o2m k=" k " x=" x " y=" y;
run;
