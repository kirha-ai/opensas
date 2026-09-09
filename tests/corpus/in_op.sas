data _null_;
  input x $ n;
  if x in ("A", "C") then r = 1; else r = 0;
  if n not in (2, 4) then s = 1; else s = 0;
  put "x=" x " n=" n " r=" r " s=" s;
  datalines;
A 1
B 2
C 3
;
run;
