/* GAP-dobynoto: iterative DO with BY in any order, and BY without TO.
   - `do i=1 by 1;` open-ended counter, exits via LEAVE
   - `do j=5 by -1 until(...);` open-ended decreasing, UNTIL guard
   - `do k=1 by 2 to 6 ...;` BY before TO (SAS accepts either order)
   - `do m=1 to 6 by 2;` classic form still works */
data _null_;
  do i=1 by 1;
    if i>3 then leave;
    put "count=" i;
  end;
  put "after i=" i;

  do j=5 by -1 until(j<=2);
    put "down=" j;
  end;

  do k=1 by 2 to 6 until(k>10);
    put "byto=" k;
  end;

  do m=1 to 6 by 2;
    put "classic=" m;
  end;
run;
