data _null_;
  x = 2;
  select (x);
    when (1) put "one";
    when (2) put "two";
    otherwise put "other";
  end;
run;
