/* GAP-wherestmtops: the WHERE STATEMENT rejected BETWEEN / IS NULL / IS MISSING
   with a ParseError, though the where= dataset option accepted them. Both forms
   now share sql.desugarPredicates, so these parse identically to PROC SQL.
   BETWEEN is inclusive; IS MISSING is true for numeric . and blank char. */
data src;
  length grp $4;
  n = 5;  grp = "A"; output;
  n = 10; grp = "B"; output;
  n = 20; grp = "C"; output;
  n = 25; grp = "D"; output;
  n = .;  grp = " "; output;
run;

/* inclusive BETWEEN → 10 and 20 kept (5 and 25 out, missing out) */
data btw; set src; where n between 10 and 20; run;
proc print data=btw noobs; run;

/* numeric IS MISSING → the . row */
data miss; set src; where n is missing; run;
proc print data=miss noobs; run;

/* char IS NULL (blank) → the blank-grp row */
data blank; set src; where grp is null; run;
proc print data=blank noobs; run;

/* NOT BETWEEN keeps 5, 25 and the missing row (. is < any bound) */
data notbtw; set src; where n not between 10 and 20; run;
proc print data=notbtw noobs; run;
