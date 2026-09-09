/* QA regression (BUG-yearcutoff fixed, both paths): 2-digit years expand via
   SAS 9.4 default YEARCUTOFF=1926 -> window [1926,2025]. input() FUNCTION path. */
data _null_;
  a=input("16JAN20", date7.);
  b=input("01/15/20", mmddyy8.);
  c=input("16JAN25", date7.);
  d=input("16JAN26", date7.);
  e=input("16JAN99", date7.);
  f=input("16JAN2020", date9.);
  put "y20=" a;
  put "y20_mmddyy=" b;
  put "y25=" c;
  put "y26_boundary=" d;
  put "y99=" e;
  put "y4digit=" f;
run;
