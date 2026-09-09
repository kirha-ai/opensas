data _null_;
  array a{3} (5 10 15);
  array b{5} (10 20 30 40 50);
  da = dim(a); sa = sum(of a{*}); a2 = a{2};
  db = dim(b); sb = sum(of b{*}); b3 = b{3};
  put "a_dim_sum_a2=" da sa a2;
  put "b_dim_sum_b3=" db sb b3;
run;
