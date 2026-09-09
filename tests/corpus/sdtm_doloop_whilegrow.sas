/* Titrate a dose by doubling while under a ceiling (DO WHILE) */
data titrate;
  dose = 25;
  week = 0;
  do while (dose < 200);
    dose = dose * 2;
    week = week + 2;
  end;
  keep dose week;
run;
proc print data=titrate; run;
