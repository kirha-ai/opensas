data _null_;
  /* no-match is fine when an OTHERWISE is present; only no-match WITHOUT
     OTHERWISE fails loud (that error path is covered by the in-file test). */
  do x = 1, 5;
    select (x);
      when (1) put "one";
      otherwise put "other";
    end;
  end;
run;
