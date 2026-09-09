/* BUG-tabinlinelabel: inline `elem='label'` overrides in the TABLE statement
   head the columns. `r='Region'` renames the row var, `v='Value'` the analysis
   var, and `all='Total'` the ALL column — they used to be silently dropped so
   the headers printed the raw names r / v / All. (The bare `all` element has
   no associated statistic, so it defaults to N — Procedures Guide p.2547:
   "Otherwise, the default statistic is N" — GAP-tabulateforms #7; it used to
   repeat the v block's Sum.) Second table: an inline label WINS over a LABEL
   statement for that table (Amount, not Money). */
data d;
  input r $ v;
  datalines;
east 10
west 20
east 30
west 40
;
run;
proc tabulate data=d;
  class r;
  var v;
  table r='Region', v='Value'*sum all='Total';
run;
proc tabulate data=d;
  class r;
  var v;
  label v='Money';
  table r, v='Amount'*sum;
run;
