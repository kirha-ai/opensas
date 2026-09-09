/* STMT-ranges: KEEP/DROP/RETAIN statements expand numbered ranges a1-a3
   (option-side keep=/drop= fixed by bd905b6; this is the statement side).
   Previously a loud ParseError. */
data d;
  do i = 1 to 3;
    a1 = i; a2 = i * 10; a3 = i * 100; b = i;
    output;
  end;
  keep a1-a3;
run;

proc print data=d; run;

data e;
  set d;
  drop a2-a3;
run;

proc print data=e; run;

/* retain range with a shared init, and a negative init after a range —
   `-` before a name is a range, before a number an initial value */
data r;
  retain s1-s2 0 neg -5;
  do i = 1 to 3;
    s1 = s1 + i;
    s2 = s2 + i * 2;
  end;
  put s1= s2= neg=;
run;
