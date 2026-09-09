data _null_;
  a = cat(1,'x');
  b = cats(1,'x');
  c = catt(1,'x');
  d = catx('|',1,'x');
  put a= / b= / c= / d=;
run;
