/* QA regression (BUG-setend/SETVAR-end fixed): SET end= flags the last obs.
   Fires only on the final observation, incl across concatenated datasets. */
data a; input x; datalines;
1
2
;
run;
data b; input x; datalines;
3
4
5
;
run;
data _null_; set a b end=eof;
  n + 1;
  if eof then put "LAST at n=" n " x=" x;
  else put "row n=" n " x=" x;
run;
