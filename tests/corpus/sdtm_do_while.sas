/* Accumulate visits until a threshold (DO WHILE) */
data titrate;
  dose = 10;
  day = 0;
  do while (dose < 80);
    dose = dose * 2;
    day = day + 7;
  end;
run;
proc print data=titrate; var dose day; run;
