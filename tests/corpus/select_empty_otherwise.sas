data _null_;
  /* bodyless `otherwise;` is VALID SAS — "do nothing for unmatched values",
     suppressing the no-match error (BUG-emptyotherwise). x=2 matches no WHEN
     and produces no output and no error; x=1 still prints. */
  do x = 1, 2;
    select (x);
      when (1) put "one";
      otherwise;
    end;
  end;
run;
