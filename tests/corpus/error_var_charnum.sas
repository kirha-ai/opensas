data _null_;
  length n 8;
  input s $;
  n = s;
  put "row=" _n_ " err=" _error_;
  datalines;
abc
5
xyz
;
run;
