/* BUG-sqlupdatecase: CASE on an UPDATE ... SET RHS used to write MISSING to every
   row (parser_expr has no case-expr, so `case` lexed as a bare variable → missing).
   First UPDATE: constant arms (no column ref) — proves the CASE itself works.
   Second UPDATE: arms reference the row's own column — proves per-row binding. */
data one;
  input id x;
  datalines;
1 10
2 20
3 30
;
run;
proc sql;
  update one set x = case when id=2 then 999 else 111 end;
  select id, x from one;
  update one set x = case when id>1 then x*10 else x end;
  select id, x from one;
quit;
