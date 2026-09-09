/* Nested DO accumulating a weighted score */
data score;
  total = 0;
  do visit = 1 to 3;
    do domain = 1 to 2;
      total = total + visit * domain;
    end;
  end;
  keep total;
run;
proc print data=score; run;
