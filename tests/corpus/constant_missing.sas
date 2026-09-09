/* GAP-constmissing: the documented CONSTANT names we lacked (doc p.555) and
   EXACTINT's nbytes arg. *RECIP == the base value on IEEE hardware; the LOG*
   take an optional base (default E). Unknown names / bad args still fail loud
   (missing + NOTE on stderr — asserted in charfns.zig's test block). */
data _null_;
  lb  = constant('LOGBIG');
  ls  = constant('LOGSMALL');
  lm  = constant('LOGMACEPS');
  sm  = constant('SQRTMACEPS');
  br  = constant('BIGRECIP');
  sr  = constant('SMALLRECIP');
  lbr = constant('LOGBIGRECIP');
  lsr = constant('LOGSMALLRECIP');
  lb2 = constant('LOGBIG', 10);
  x8  = constant('EXACTINT');
  x6  = constant('EXACTINT', 6);
  x3  = constant('EXACTINT', 3);
  x2  = constant('EXACTINT', 2);
  put lb= ls= lm= sm=;
  put br= sr=;
  put lbr= lsr= lb2=;
  put x8= x6= x3= x2=;
run;
