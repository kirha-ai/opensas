/* BUG-wherefunc (WHERE statement half): a where STATEMENT predicate calling a
   function silently misfiltered since 8b9b473 — applyWhereStmt's evaluator had
   no call_fn and a junk diags sink, so upcase(...) evaluated to missing: char
   compares passed EVERY row, numeric compares dropped every row, exit 0. */
data src;
  length out $12;
  out = "Fatal";     output;
  out = "RECOVERED"; output;
run;
data a; set src; where strip(upcase(out)) = "FATAL"; run;
proc print data=a noobs; run;
data b; set src; where length(out) > 6; run;
proc print data=b noobs; run;
