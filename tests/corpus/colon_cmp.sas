data _null_;
  x = 'TUMOR';
  if (x ^=: 'T') then y = 0; else y = 1;
  if (x =: 'T') then z = 1; else z = 0;
  if (x =: 'TUX') then p = 1; else p = 0;
  if (x ge: 'TU') then q = 1; else q = 0;
  put x= y= z= p= q=;
run;
