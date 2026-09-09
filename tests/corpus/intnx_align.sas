data _null_;
  d = mdy(3, 15, 2020);
  b = intnx("month", d, 2);
  m = intnx("month", d, 0, "middle");
  e = intnx("month", d, 2, "end");
  s = intnx("month", d, 2, "same");
  put "b=" b date9. " m=" m date9.;
  put "e=" e date9. " s=" s date9.;
run;
