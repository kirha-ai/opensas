/* GAP-odsbatch: ODS destination wraps are accepted-as-listing no-ops —
   opensas renders to ONE output stream, so `ods pdf; … ods pdf close;`
   around a PROC must still run and print the listing (no file created).
   The result-changing sub-statements (SELECT/EXCLUDE/OUTPUT/TRACE) fail
   loud instead — covered by the GAP-odsbatch test in src/main.zig. */
data c;
  input name $ age;
  datalines;
Alfred 14
Alice 13
Barbara 13
;
run;
ods pdf file="x.pdf";
proc print data=c(obs=2);
run;
ods pdf close;
ods listing close;
ods listing;
proc printto; run;
