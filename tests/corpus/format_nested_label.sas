/* BUG-fmtnestlabel: a VALUE range may name ANOTHER format as its label —
   `range=[fmtname w.d]` (SAS directed formatting). The bracketed format renders
   the value at apply time. opensas's entry parser only accepted a quoted label,
   so the bracket tokens hit the silent skip and the entry rendered EMPTY. */
proc format;
  value bnest low-<100=[dollar8.2] 100-high='big';
  value $yn "Y"="Yes" "N"="No" other=[$quote.];
run;
data _null_;
  x = 42.5; y = put(x, bnest.); put "low " y=;
  x = 150;  y = put(x, bnest.); put "high " y=;
  z = put("Y", $yn.); put "yn_Y " z=;
  z = put("?", $yn.); put "yn_other " z=;
run;
