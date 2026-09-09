/* Classic LAG gotcha: LAG builds its queue only on the executions that
   actually run. Calling LAG2 inside a conditional branch advances its
   2-deep queue only on the rows where x>2, so the value returned is the
   x from two QUALIFYING rows back -- not two physical rows back.
   Unconditional lag()/dif() advance every row for contrast. */
data _null_;
  input x @@;
  prev = lag(x);
  d    = dif(x);
  if x > 2 then cond = lag2(x);
  put "x=" x " lag=" prev " dif=" d " cond=" cond;
  datalines;
1 5 2 8 3
;
run;
