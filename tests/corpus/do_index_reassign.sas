/* BUG-doindexreassign: an iterative DO must honor a body reassignment of the
   index — the altered value is what the bottom-of-loop step increments and what
   the TO bound is tested against. Normal loops that never touch the index are
   the control (final index = stop + by). */
data _null_;
  do i = 1 to 10;
    if i = 3 then i = 100;
  end;
  put "reassign i=" i;

  do j = 1 to 10;
  end;
  put "normal j=" j;

  do k = 1 to 3;
    k = k + 1;
  end;
  put "jump k=" k;
run;
