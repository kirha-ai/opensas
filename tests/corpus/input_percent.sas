data _null_;
  compliance = input("85%", percent8.);
  responder = input("100%", percent8.);
  none = input("0%", percent5.);
  frac = input("0.5", percent8.);
  put "compliance=" compliance " responder=" responder " none=" none " frac=" frac;
run;
