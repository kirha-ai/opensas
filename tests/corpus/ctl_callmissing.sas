data _null_;
  length s $3;
  x = 42; s = "abc"; other = 7;
  call missing(x, s);
  if missing(x) then put "x missing";
  if s = "" then put "s blank";
  put "other=" other;
run;
