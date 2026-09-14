/* e8601dnz: E8601DNw./E8601DZw.d informats + the E8601DZw. format — GH#5a
   ISS-e8601dndz. DN (Informats Reference p.642: "The width of the input field
   must be 10") reads ISO yyyy-mm-dd as a midnight DATETIME; incomplete values
   are invalid data and read missing. DZ (p.645: w 20-35) reads the UTC-offset
   complete form and rebases to the zero meridian (local - offset); a trailing
   Z is offset 0 and a field with no offset is invalid. The DZ FORMAT (p.204:
   Default 26, Alignment Left) appends +00:00 and drops to the Z short form
   below w=25. Doc anchors: 2018-09-15 -> 1852588800;
   2018-09-15T15:53:00Z -> 1852645980. Invented data. */
data _null_;
  a1 = input("2018-09-15", e8601dn10.);
  put "a1=" a1;
  a2 = input("2025-01", e8601dn10.);
  put "a2=" a2;
  a3 = input("2025", e8601dn10.);
  put "a3=" a3;
  a4 = input("2018-09-15T15:53:00Z", e8601dz26.);
  put "a4=" a4;
  a5 = input("2025-01-16T13:53:00+05:00", e8601dz26.);
  put "a5=" a5;
  a6 = input("2025-01-16T13:53:00-05:00", e8601dz26.);
  put "a6=" a6;
  a7 = input("2025-01-16T13:53:00", e8601dz26.);
  put "a7=" a7;
run;
data one;
  /* statement path: the column read hands over w=10 columns */
  input dt e8601dn10.;
  put "s1=" dt;
datalines;
2018-09-15
;
run;
data _null_;
  dt = '15sep2018:05:53:00'dt;
  put "dz=" dt e8601dz. "|";
  put "dz25=" dt e8601dz25. "|";
  put "dz24=" dt e8601dz24. "|";
  put "dz20=" dt e8601dz20. "|";
  /* the DN format takes a DATETIME and writes its date part (p.199) */
  put "dn=" dt e8601dn10. "|";
run;
