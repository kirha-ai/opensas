data _null_;
  do x = 0 to 6;
    if x in (1:3, 5) then put x " IN";
    else put x " OUT";
  end;
  s = 'b';
  if s in ('a', 'b') then put "char IN";
run;
