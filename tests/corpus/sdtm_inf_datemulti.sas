/* Several date informats resolve to the same SAS date value */
data d;
  d1 = input("01/15/2024", mmddyy10.);
  d2 = input("15/01/2024", ddmmyy10.);
  d3 = input("2024-01-15", yymmdd10.);
  d4 = input("15JAN2024", date9.);
  allsame = (d1 = d2) and (d2 = d3) and (d3 = d4);
  put "d1=" d1 " allsame=" allsame;
run;
