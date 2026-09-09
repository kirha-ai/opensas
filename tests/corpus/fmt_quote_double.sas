/* NOTE-fmtquotedouble: $QUOTEw. doubles an embedded double quote before
   wrapping — the same CSV/DSD escape the QUOTE() function, the FILE DSD writer
   and PROC EXPORT already shared, and the rule the INFILE DSD reader collapses
   back (BUG-dsddoublequote). Undoubled output ("a"b") could not be read back
   by any DSD reader, opensas's own included. */
data _null_;
  length v $12;
  v = 'a"b';
  put '[' v $quote12. ']';
  put '[' v $quote. ']';
  w = quote(v);   /* the function already doubled — format now agrees */
  put '[' w ']';
run;
