/* e8601dt_width: E8601DTw. honors its width — GH#2 ISS-e8601dt-width.
   Formats and Informats Reference pp.200-201: w Default 19, Range 16-26,
   Alignment Left; at w=16 SAS assumes the seconds are 0 and omits them, and
   w 20-26 blank-pad the RIGHT of the value. The informat twin (pp.643-644)
   slices to w the same way, so e8601dt16. reads the seconds as 00.
   The "|" pins the field width: no blank may move across it. Invented data. */
data _null_;
  dt = '16jan2025:13:53:45'dt;
  put "w16=" dt e8601dt16. "|";
  put "def=" dt e8601dt. "|";
  put "w19=" dt e8601dt19. "|";
  put "w20=" dt e8601dt20. "|";
  put "w26=" dt e8601dt26. "|";
  r = input("2025-01-16T13:53:45", e8601dt16.);
  put "r16=" r e8601dt19. "|";
run;
data one;
  /* column input reads exactly w columns: 1-16, so the seconds never read */
  input dt e8601dt16.;
  put "c16=" dt e8601dt19. "|";
datalines;
2025-01-16T13:53:45
;
run;
