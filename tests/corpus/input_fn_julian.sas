/* BUG-julianinputfn: the INPUT() FUNCTION must route JULIANw. to the packed
   Julian parser (format.readNumeric) like the INPUT statement does
   (BUG-julianinformat, caad83a). Was: fell to the plain numeric read and
   silently returned the raw digits. 1960 day 011 = SAS day 10; 1900 is not
   a leap year, so day 366 is invalid -> missing. */
data _null_;
  a = input("1960011", julian7.);
  b = input("1900366", julian7.);
  c = input("60011", julian5.);
  d = put(a, date9.);
  put a= b= c= d=;
run;
