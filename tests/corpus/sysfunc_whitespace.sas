/* BUG-sysfunctrim: %sysfunc must NOT trim whitespace off arguments —
 * macro whitespace is significant. Brackets in put make blanks visible.
 * Expected values are the SAS 9.4 results. */
%let r1 = %sysfunc(tranwrd(a b c,%str( ),_));
%let r2 = %sysfunc(catx(%str( ),a,b,c));
%let r3 = %sysfunc(repeat(%str( ),3));
%let r4 = %sysfunc(reverse(  hi));
%let n1 = %sysfunc(upcase(abc));
%let n2 = %sysfunc(sum(1,2,3));
data _null_;
  put "r1=&r1";
  put "r2=&r2";
  put "r3=[&r3]";
  put "r4=[&r4]";
  put "n1=&n1 n2=&n2";
run;
