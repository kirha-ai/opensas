/* PUT a numeric then INPUT it back under matching informats (comma/dollar/w.d) */
data d;
  x = 1234567.89;
  length sc $14 sd $16;
  sc = put(x, comma14.2);
  sd = put(x, dollar16.2);
  yc = input(sc, comma14.2);
  yd = input(sd, dollar16.2);
  okc = (round(yc,0.01) = round(x,0.01));
  okd = (round(yd,0.01) = round(x,0.01));
  put "okc=" okc " okd=" okd;
run;
