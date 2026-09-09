/* Iterative DO accumulating a running total and count */
data series;
  total = 0;
  do k = 1 to 5;
    total = total + k * k;
  end;
  mean_sq = total / 5;
  keep total mean_sq;
run;
proc print data=series; run;
