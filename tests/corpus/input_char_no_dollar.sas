/* BUG-inputcharnodollar: a BARE `input nm;` (list input, no `$`/informat) on a
   variable ALREADY declared CHARACTER (LENGTH/ATTRIB) reads a CHAR token per the
   declared type — not a numeric read (which turned "ABC" into missing). Explicit
   `$`, colon informats, and numeric bare reads are unchanged; a declared $8
   truncates a longer token to the declared length. */
data d;
  length nm $8;
  input nm;
  datalines;
ABC
XYZ
;
run;
proc print data=d; run;

data n;
  input x;
  datalines;
42
;
run;
proc print data=n; run;

data m;
  length a $8 b $3;
  input a b $;
  datalines;
hello world
;
run;
proc print data=m; run;

data dlm;
  infile datalines dlm=',';
  length nm $8;
  input nm x;
  datalines;
AB,7
;
run;
proc print data=dlm; run;
