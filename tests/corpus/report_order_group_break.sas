/* QA tick205 GREEN: composition guard for the ORDER+GROUP collation rework
   (a36edfd, BUG-reportordergroupmix). Mixes an ORDER var (region) with a GROUP
   var (prod) AND break-after/rbreak SUMMARIZE. Verifies all three compose:
   each (region, prod) is one summed row ordered by region then prod, repeated
   ORDER values blank, the break-after line shows the region value with its
   subtotal, and the grand total blanks it. Hand-verified sums:
     East A 3+2=5, East B 5+6=11 -> East subtotal 16
     West A 10+4=14, West B 7+1=8 -> West subtotal 22, grand 38. */
data d;
  input region $ prod $ sales;
  datalines;
West A 10
East B 5
West B 7
East A 3
West A 4
East B 6
East A 2
West B 1
;
run;

proc report data=d nowd;
  column region prod sales;
  define region / order;
  define prod   / group;
  define sales  / analysis sum;
  break after region / summarize;
  rbreak after / summarize;
run;
