/* E8601DA-packed-input: the packed ISO date form yyyymmdd (no separators, e.g.
   B8601DA) must read to a SAS day on the DATA-step INPUT-statement path, not
   just via the input() function. All packed reads want 23390 (2024-01-15);
   the separated form still reads too (regression). */
data _null_;
  input @1 d b8601da8.;
  put "STMT=" d;
  datalines;
20240115
;
run;

data _null_;
  input d : b8601da8.;
  put "MOD=" d;
  datalines;
20240115
;
run;

data _null_;
  x = '20240115'; d = input(x, b8601da8.);
  put "FUNC=" d;
run;

data _null_;
  input @1 d e8601da10.;
  put "SEP=" d;
  datalines;
2024-01-15
;
run;
