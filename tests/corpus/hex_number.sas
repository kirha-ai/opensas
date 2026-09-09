data _null_;
  a = 0fx;      /* 15 */
  b = 1Fx;      /* 31, case-insensitive digits and X */
  c = 9x;       /* 9, single hex digit */
  d = 0b0ax;    /* 2826 */
  max = 100;    /* guard: an identifier ending in x stays a variable */
  xx = max + 1; /* 101 */
  put a= b= c= d= max= xx=;
run;
