/* E-notation input and large-magnitude values under BEST display */
data d;
  small = 1.23e-4;
  big   = 4.56e8;
  huge  = 1e12;
  neg   = -7.8e-3;
  put "small=" small;
  put "big=" big;
  put "huge=" huge;
  put "neg=" neg;
run;
