data d;
  length name $ 20 city $ 15;
  name = "Alice"; city = "Rome"; age = 30;
  output;
run;
proc contents data=d order=varnum; run;
proc contents data=d position; run;
proc contents data=d order=ignorecase; run;
