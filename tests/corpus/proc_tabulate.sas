data have;
  input region $ sales;
  datalines;
East 100
West 200
;
run;

proc tabulate data=have;
  class region;
  var sales;
  table region, sales*sum;
run;
