data _null_;
  x = 1;
  putlog "x=" x;
  putlog x=;
  putlog "done";
  put "put-still-works";
run;
