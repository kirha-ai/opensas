/* e8601dt_width: E8601DTw. honors its width — GH#2 ISS-e8601dt-width.
   Formats and Informats Reference pp.200-201: w Default 19, Range 16-26; at
   w=16 SAS assumes the seconds are 0 and omits them. Padding side is
   RUNTIME-verified (GH#11 ISS-e8601rightalign): every padded width
   RIGHT-justifies (LEADING blanks) — the entry's `Alignment: Left` header
   field is not oracle (decisions.md D-025). The informat twin (pp.643-644)
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
/* GH#11 discriminator (the issue's probe program): length() returns the
   position of the last non-blank, so leading padding pins len=w (16/19/20/26)
   where trailing padding collapses w>19 to 19; $quote30. prints the stored
   value verbatim — real SAS puts all 7 blanks INSIDE the opening quote. */
data _null_;
  base = '16jan2025:13:53:00'dt;
  f16 = put(base, e8601dt16.);
  f19 = put(base, e8601dt19.);
  f20 = put(base, e8601dt20.);
  f26 = put(base, e8601dt26.);
  n16 = length(f16);
  n19 = length(f19);
  n20 = length(f20);
  n26 = length(f26);
  put "f16 <" f16 "> len=" n16;
  put "f19 <" f19 "> len=" n19;
  put "f20 <" f20 "> len=" n20;
  put "f26 <" f26 "> len=" n26;
  put "f26=" f26 $quote30.;
run;
data one;
  /* column input reads exactly w columns: 1-16, so the seconds never read */
  input dt e8601dt16.;
  put "c16=" dt e8601dt19. "|";
datalines;
2025-01-16T13:53:45
;
run;
