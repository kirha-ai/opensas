/* GAP-fileprint: `file print;`/`file log;` were rejected with "expected a file
   path". They are standard PUT targets: PRINT routes to the listing, LOG to the
   SAS log — opensas has one stdout stream for both (main.zig), so both keywords
   route PUT to the normal log output and NO file named print/log is written.
   A following `file print;` after an external FILE reverts PUT to the listing;
   DLM= is still honored on the keyword form. */
data _null_;
  file print;
  put "hello";
run;
data _null_;
  file log;
  put "x";
run;
data _null_;
  file print dlm=",";
  a = 1; b = 2;
  put a b;
run;
