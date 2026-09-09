/* BUG-nesteddeclarative: RETAIN nested inside an IF-THEN/ELSE branch is a
   compile-time declarative in SAS — it registers its retain flag regardless of
   the runtime branch that (never) executes it. c is retained via a THEN-DO
   branch, w via an ELSE-DO branch; both accumulate instead of resetting to
   missing each row. top is an ordinary top-level RETAIN — must stay unchanged. */
data _null_;
  input x;
  if _n_ = 1 then do; retain c 100; end;
  else do; retain w 50; end;
  retain top 0;
  c = c + 1;
  w = w + 1;
  top = top + x;
  put "c=" c "w=" w "top=" top;
  datalines;
1
2
3
;
run;
