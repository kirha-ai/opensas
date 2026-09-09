data _null_;
  array v{3} v1-v3 (1 2 3);
  do i = 1 to 3;
    v{i} = v{i} ** 2;
  end;
  put "v1=" v1 " v2=" v2 " v3=" v3;
run;
