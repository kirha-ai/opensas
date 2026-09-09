/* PUT accepts subscripted (a[i]/a{i}) and whole-array (a[*]) refs; [ ] and { }
   are interchangeable in declaration and reference (BUG-putarrayref) */
data _null_;
  array b{3} b1-b3 (5 10 15);
  do i = 1 to 3;
    put "brace i=" i " val=" b{i};
  end;
  array c[3] c1-c3 (1 2 3);
  put "bracket-all " c[*];
  x = c[2];
  put "elem c[2]=" x;
run;
