/* PUT @n column pointer: position the output column before writing (PG-atptr) */
data _null_;
  x = 5;
  put @10 x;
  put "id" @6 "val";
  a = 1; b = 2;
  put @3 a @8 b;
run;
