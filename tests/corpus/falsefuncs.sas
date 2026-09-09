/* F-falsefuncs audit: functions once flagged as false [x] are implemented and
   correct. Regression guard. */
data _null_;
  g = gamma(5);      /* 4! = 24 */
  b = beta(2, 3);    /* B(2,3) = 1/12 */
  s = std(2, 4, 6);  /* sample std = 2 */
  w = week('15MAR2021'd);
  length c $8;
  c = cat("ab", "cd");
  x = 5; y = "hi";
  call missing(x, y);
  put "gamma=" g;
  put "beta=" b 12.10;
  put "std=" s;
  put "week=" w;
  put "cat=" c;
  put "missing_x=" x " y=[" y "]";
run;
