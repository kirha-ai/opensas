/* BEST display: integers, decimals, and E-notation chosen automatically */
data d;
  length lbl $20;
  do i = 1 to 5;
    v = choosen(i, 42, 3.14159, 1000000, 0.000123, 123456789012);
    lbl = put(v, best12.);
    output;
  end;
  keep i v lbl;
run;
proc print data=d; var v lbl; run;
