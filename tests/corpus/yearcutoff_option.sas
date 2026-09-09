/* BUG-yearcutoffstmt: `options yearcutoff=1950;` must wire into the shared
   YEARCUTOFF span (was parsed then DROPPED -> 2-digit years kept the 1926
   default = silent wrong dates). Window [1950,2049]: 49 -> 2049. */
options yearcutoff=1950;
data _null_;
  a = input('01jan49', date9.);     put a year4.;
  b = input('01/15/49', mmddyy10.); put b year4.;
  c = input('49011', julian5.);     put c year4.;
run;
/* re-applying the option moves the window back: 49 -> 1949 again */
options yearcutoff=1926;
data _null_;
  d = input('01jan49', date9.);     put d year4.;
run;
