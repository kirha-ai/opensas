/* sci_format: Z (zero-pad) / E (scientific) / BEST / PERCENT write formats. Phase-G. */
data _null_;
  n = 1234567.89; p = 0.256; k = 22100;
  put "Z="       k z8.;
  put "E="       n e12.;
  put "BEST="    n best12.;
  put "PERCENT=" p percent8.1;
run;
