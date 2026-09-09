/* GAP-pathname: PATHNAME(libref) returns the directory bound by LIBNAME
   (blank for an unknown ref). Surfaced by a real SDTM AE program right
   after the zero-obs domino chain fell. */
libname l "tests/programs/sas7bdat_read/inputs";
%let mp = %sysfunc(pathname(l));
data _null_;
  p = pathname('l');
  ok = (p = "&mp");     /* %sysfunc text route agrees with the data-step route */
  u = (pathname('nope') = '');
  put p= ok= u=;
run;
