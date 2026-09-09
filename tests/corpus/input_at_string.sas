/* GAP-inputatstring: INPUT `@'string'` column pointer — advance the input
   pointer to JUST AFTER the next occurrence of the literal in the current
   record, then read from there (companion to SCANOVER). Not found → pointer
   to end of line (MISSOVER: the following read gets missing, no error).
   Plain `@n` column controls stay unchanged. */
data mark;
  input @'AGE:' age;
  put "age=" age;
datalines;
NAME=X AGE: 42
AGE:7 REST
;
run;

data miss;
  infile datalines missover;
  input @'NOPE:' x;
  put "x=" x;
datalines;
abc 123
;
run;

data plain;
  input @3 y 2.;
  put "y=" y;
datalines;
AB12
;
run;
