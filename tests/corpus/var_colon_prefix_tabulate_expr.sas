/* GAP-varcolonprefix-procs: a prefix inside a TABULATE TABLE EXPRESSION is
   a crossing position the doc never settles (the FREQ TABLES grouping doc,
   Statistical Procedures 6th ed. printed p.103 Table 3.8, covers parens
   and name ranges only) — so it stays LOUD (rc 2 gap). It used to be worse
   than silent: the colon was skipped and `x:` parsed as a phantom row
   variable `x`, dying later with a confusing "row variable not found".
   The unambiguous position — the CLASS statement — does expand (see
   var_colon_prefix_procs.sas).
   expect-rc: 2 */
data t;
  x1 = 1; y = 2;
run;
proc tabulate data=t;
  class y;
  table x:, y*sum;
run;
