/* BUG-informatreadloud: MONYY and YYQ read informats. Before the fix these
   unimplemented informats fell through to the numeric parser and SILENTLY read
   missing (clinical date columns became all-missing at exit 0). MONYYw. reads a
   month-year to the 1st of that month; YYQw. reads a year-quarter to the 1st of
   the quarter's first month (Language Reference: Concepts "MONYYw./YYQw. Informats"). Both the INPUT()
   function and the INPUT statement route to the same reader. */
data _null_;
  a = input('MAR2020', monyy7.);
  b = input('2020Q2', yyq6.);
  c = input('DEC20',  monyy5.);
  put a= date9. b= date9. c= date9.;
run;
data dates;
  input @1 mon monyy7. @9 qtr yyq6.;
  datalines;
JAN2021 2021Q4
;
run;
data _null_;
  set dates;
  put mon= date9. qtr= date9.;
run;
