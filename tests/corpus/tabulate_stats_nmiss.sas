/* Regression guard for BUG-tabnmiss (c9085ae): NMISS now renders the cell's
   missing-obs count (obs - n). This locks that the change left N/Sum/Mean/
   PctN/PctSum AND the ALL grand-total column unchanged, and that NMISS is
   correct on the ALL row (total obs - grand n). g=a: 3 obs, 1 missing (n=2);
   g=b: 2 obs, 0 missing (n=2); ALL: 5 obs, 1 missing (n=4). */
data d;
  input g $ v;
  datalines;
a 10
a .
a 30
b 40
b 50
;
run;
proc tabulate data=d;
  class g;
  var v;
  table g all, v*(n nmiss sum mean pctn pctsum);
run;
