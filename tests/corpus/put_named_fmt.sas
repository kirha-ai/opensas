data _null_;
  a = 0.123456789;
  x = 12345.678;
  format x dollar12.2;
  put a= dollar10.2;   /* inline named + format */
  put x=;              /* named honours attached FORMAT */
  put x;               /* plain: attached format still applies */
  put a dollar10.2;    /* inline (no =) format guard */
run;
