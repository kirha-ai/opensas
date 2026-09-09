/* BUG-infilebufvar: `_INFILE_` is a character automatic holding the raw current
   input record (the buffer just read by INFILE/INPUT). Was: zero refs in src —
   a reference created a fresh uninitialized NUMERIC var yielding `.` plus a
   misleading "uninitialized" NOTE. It must yield the raw record text, and must
   NOT become an output column (automatic). */
data d;
  infile datalines;
  input a b;
  raw = _infile_;
  put "RAW=[" raw "]";
datalines;
10 20
30 40
;
run;

proc print data=d; run;

data e;
  input x $ @@;
  rec = _infile_;
  datalines;
p q r
;
run;

data _null_;
  set e;
  put "E=[" rec "] x=" x;
run;
