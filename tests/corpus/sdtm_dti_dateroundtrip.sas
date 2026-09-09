/* INPUT a date in each format, PUT back, confirm the SAS day is stable */
data d;
  a = input("2024-07-04", yymmdd10.);
  b = input("07/04/2024", mmddyy10.);
  c = input("04/07/2024", ddmmyy10.);
  allsame = (a = b) and (b = c);
  length back $9;
  back = put(a, date9.);
  put "a=" a " allsame=" allsame " back=" back;
run;
