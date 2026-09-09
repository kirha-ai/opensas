/* GAP-varcolonprefix-procs: PROC FREQ's TABLES is THE hard case — a prefix
   INSIDE a `*` crossing has its own expansion question, and the doc is
   silent on it: Statistical Procedures 6th ed. printed p.103 (a request is
   "one variable name or several variable names separated by asterisks")
   and its Table 3.8 document grouping syntax distributing PARENTHESIZED
   lists and NAME-RANGE lists over crossings, never the name-prefix form.
   So the crossing stays LOUD (rc 2 gap), never guessed; only the one-way
   position expands (see var_colon_prefix_procs.sas).
   expect-rc: 2 */
data t;
  x1 = 1; x2 = 2; y = 3;
run;
proc freq data=t;
  tables x:*y;
run;
