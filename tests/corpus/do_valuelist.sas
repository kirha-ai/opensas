data _null_;
  do i = 1, 3, 5, 3 to 5;
    put "i=" i;
  end;
  /* char value list — each string is one iteration (was silent 0-loop: G-dolist) */
  do c = "a", "b", "c";
    put "c=" c;
  end;
run;
