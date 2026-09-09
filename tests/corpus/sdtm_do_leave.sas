/* Iterate then break out of the loop early (DO + LEAVE) */
data d;
  do i = 1 to 10;
    if i = 6 then leave;
    x = i * i;
    output;
  end;
  keep i x;
run;
proc print data=d; run;
