/* Many-to-many MERGE quirk (SAS 9.4 documented, easy to get wrong): when BOTH
   datasets have duplicate BY values with UNEQUAL group sizes, SAS pairs rows
   positionally and, once the SHORTER side is exhausted, RETAINS its last value
   for the remaining rows of the longer side. It does NOT do a SQL-style cross
   product. Here a has 2 rows for id=1, b has 3 → row 3 keeps a's last x (11). */
data a; input id x; datalines;
1 10
1 11
2 5
;
run;
data b; input id y; datalines;
1 100
1 101
1 102
2 50
2 51
;
run;
data _null_;
  merge a b;
  by id;
  put "id=" id " x=" x " y=" y;
run;
