proc format;
  value grp
    low - <10 = "under10"
    10 - <20 = "teens"
    20 - high = "twentyplus";
  value ex 0<-10 = "gt0to10";
run;
data _null_;
  do x = 5, 9, 10, 15, 20, 25;
    y = put(x, grp.);
    put "grp x=" x "y=" y;
  end;
  a = put(0, ex.);
  b = put(5, ex.);
  c = put(10, ex.);
  put "ex 0=" a " 5=" b " 10=" c;
run;
