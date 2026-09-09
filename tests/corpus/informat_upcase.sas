data _null_;
  /* INPUT() function form */
  fu = input('HeLLo', $upcase8.);
  fl = input('HeLLo', $lowcase8.);
  /* INPUT statement form ($UPCASE reads fixed width, then upcases) */
  input sv $upcase5.;
  put "fu=" fu " fl=" fl " sv=" sv;
  datalines;
abcde
;
run;
