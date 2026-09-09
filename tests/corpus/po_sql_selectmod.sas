data d; x=3.14159; y=2; output; run;
proc sql;
  select x as a format=dollar10.2, y as b from d;
quit;
proc sql;
  select x as a label='XX', y format=best8. from d;
quit;
