/* ISS-charnumassign: assigning a character value to a NUMERIC variable must
   convert the SAS way (implicit BEST input) and be LOUD — the conversion NOTEs
   go to stderr (not this stdout diff); here we pin the resulting values so a
   silent-drop regression (or a wrong conversion) shows up.

   n = "hello"  -> . (invalid numeric data -> missing)
   n = "123"    -> 123 (valid numeric string converts)
   RFICDTC (typed numeric by the LENGTH template, the EMPTY_&dom idiom) gets a
   char date assigned -> . (unparsable -> missing), never the day-number. */
data _null_;
  n = 5;
  n = "hello";
  put "a n=" n=;
  n = "123";
  put "b n=" n=;
run;

data TMPL; length RFICDTC 8; stop; run;
data SRC;  ICDTC_ = "03OCT2022"; run;
data _null_;
  set TMPL SRC;
  RFICDTC = "2022-10-03";
  put "c RFICDTC=" RFICDTC=;
run;
