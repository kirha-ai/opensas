data d;
  length name $ 20 city $ 15;
  label name = "Person Name" city = "City Name";
  format age 3.;
  name = "Alice"; city = "Rome"; age = 30;
  output;
run;
proc contents data=d; run;
