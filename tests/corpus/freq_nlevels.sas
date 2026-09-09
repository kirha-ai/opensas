data d;
  input g $ x;
  datalines;
A 1
A 2
B 3
C 4
C 5
;
run;

/* NLEVELS alone: the "Number of Variable Levels" table (g has 3, x has 5). */
proc freq data=d nlevels;
  tables g;
  tables x;
run;

/* NLEVELS combined with a normal one-way TABLES request: the NLEVELS table
   prints FIRST, then the frequency table (ordering pin). */
proc freq data=d nlevels;
  tables g;
run;
