/* Iterate until convergence (Newton sqrt of 2) with DO UNTIL */
data root;
  x = 1;
  iter = 0;
  do until (abs(x*x - 2) < 0.0001);
    x = (x + 2/x) / 2;
    iter = iter + 1;
  end;
  approx = round(x, 0.0001);
  keep approx iter;
run;
proc print data=root; run;
