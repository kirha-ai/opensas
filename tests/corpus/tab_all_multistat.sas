data have;
  input region $ prod $ sales;
  datalines;
East A 100
East B 50
West A 200
West B 30
;
run;
proc tabulate data=have;
  class region prod;
  var sales;
  table region all, sales*(sum mean n);
run;
