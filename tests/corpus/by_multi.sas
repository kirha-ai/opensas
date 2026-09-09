data have;
  input region $ product $ sales;
  datalines;
East A 10
East A 20
East B 30
West A 40
;
run;

data _null_;
  set have;
  by region product;
  if first.product then put "FP region=" region " product=" product;
  put "row region=" region " product=" product " sales=" sales;
  if last.product then put "LP region=" region " product=" product;
run;
