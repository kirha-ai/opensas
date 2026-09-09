/* QA tick145 regression guard: verified-correct numeric/stat functions,
   expression precedence (right-assoc **, unary-minus vs **, missing<0),
   and COALESCE/ORDINAL/PCTL/LARGEST/SMALLEST. Values checked vs SAS 9.4. */
data _null_;
  l1 = largest(2, 5, 3, 9, 1);
  s1 = smallest(2, 5, 3, 9, 1);
  o1 = ordinal(3, 10, 20, 5, 30, 15);
  m1 = median(1, 2, 3, 4);
  p1 = pctl(25, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
  co = coalesce(., ., 7, 9);
  a = 2 ** 3 ** 2;
  b = -3 ** 2;
  w = . < 0;
  neg = (-8) ** (1/3);
  put l1= s1= o1= m1= p1= co= a= b= w= neg=;
run;
