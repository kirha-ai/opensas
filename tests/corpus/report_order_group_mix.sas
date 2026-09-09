/* BUG-reportordergroupmix: PROC REPORT with an ORDER-usage var mixed with a
   GROUP-usage var. The ORDER col (region) joins the GROUP key, so each distinct
   (region, prod) is one summarized row: sales SUMmed per group, rows ordered by
   region (ORDER), then prod (GROUP). Repeated ORDER values blank in the listing.
   Before the fix the key was GROUP-only, collapsing across regions (both rows
   labelled the first region, West silently dropped). Hand-verified sums:
   East/A 3+2=5, East/B 5+6=11, West/A 10+4=14, West/B 7+1=8. */
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
run;
