data _null_;
  x = put(42, 8.2);
  y = put(3, 1.);
  z = put(42, '8.2');
  put x= / y= / z=;
run;
