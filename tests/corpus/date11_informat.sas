/* GAP-date11informat: DATE11. informat READ side — the hyphenated DD-MON-YYYY
   form parses (hyphens are separators); the packed DDMONYYYY form still reads.
   15MAR2020 = SAS day 21989. */
data _null_;
  a = input("15-MAR-2020", date11.); put "DATE11=" a;
  b = input("15MAR2020", date9.);    put "DATE9="  b;
  c = input("15MAR20", date7.);      put "DATE7="  c;
run;

data _null_;
  input d date11.;
  put "STMT=" d;
datalines;
15-MAR-2020
;
run;
