/* Nested DO computing a product-sum matrix total */
data m;
  total = 0;
  do i = 1 to 3;
    do j = 1 to 3;
      total = total + i * j;
    end;
  end;
  keep total;
run;
proc print data=m; run;
