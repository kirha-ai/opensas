data _null_;
  length c $3 x 8 z 8;
  input c $;
  x = c + 0;              /* invalid char->num on 'abc' -> _ERROR_=1 */
  if _error_ then put "row=" _n_ " conv err=" _error_;
  _error_ = 0;
  z = 5 / 0;              /* division by zero -> _ERROR_=1 */
  if _error_ then put "row=" _n_ " divz err=" _error_;
  datalines;
abc
12
;
run;
