/* Date informats via the INPUT function reject an invalid day-of-month (return
   missing) instead of rolling over. Regression guard for BUG-infdate. */
data _null_;
  a = input("31FEB2020", date9.);      /* invalid -> . */
  b = input("29FEB2020", date9.);      /* valid leap -> 21974 */
  c = input("29FEB2021", date9.);      /* not leap -> . */
  d = input("2020-02-31", yymmdd10.);  /* invalid -> . */
  e = input("15JAN2020", date9.);      /* valid -> 21929 */
  put "d31feb=" a;
  put "d29feb20=" b;
  put "d29feb21=" c;
  put "y0231=" d;
  put "d15jan=" e;
run;
