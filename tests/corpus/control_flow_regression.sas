/* QA tick163 regression net for the DATA-step control-flow refactor
   (BUG-controlflownesting, 3a0f4ea — body compiled to a flat op stream).
   Locks in control transfers the sibling control_flow_nesting.sas omits:
   LEAVE/CONTINUE/GOTO/LINK from inside a SELECT nested in a loop, nested LINK,
   value-list DO with LEAVE/CONTINUE, backward-GOTO retry, and the index value
   after normal loop exit (ascending and descending). GREEN — behaviour matches
   SAS 9.4; any drift here is a control-flow regression. */

/* LEAVE out of a SELECT that sits inside a DO loop (SELECT is not a loop). */
data _null_;
  do i = 1 to 5;
    select;
      when (i=3) leave;
      otherwise put "a i=" i;
    end;
  end;
  put "a done i=" i;
run;

/* CONTINUE from inside a SELECT skips the loop tail. */
data _null_;
  do i = 1 to 4;
    select;
      when (i=2) continue;
      otherwise put "b i=" i;
    end;
    put "b tail i=" i;
  end;
run;

/* GOTO and LINK out of a SELECT nested in a loop. */
data _null_;
  do i = 1 to 3;
    select;
      when (mod(i,2)=1) link odd;
      otherwise put "c even i=" i;
    end;
    put "c tail i=" i;
  end;
  return;
  odd: put "c odd link i=" i; return;
run;

/* Nested LINK: main -> a -> b, each RETURN resumes at its own call site. */
data _null_;
  x = 1;
  link a;
  put "d back main x=" x;
  return;
  a: x = x + 10; link b; put "d in a x=" x; return;
  b: x = x + 100; put "d in b x=" x; return;
run;

/* Value-list DO: LEAVE exits the whole list; CONTINUE moves to the next value. */
data _null_;
  do i = 1, 2, 3;
    if i = 2 then continue;
    put "e i=" i;
  end;
  do j = 1, 2, 3, 10 to 12;
    if j = 3 then leave;
    put "e j=" j;
  end;
  put "e done j=" j;
run;

/* Backward GOTO retry loop. */
data _null_;
  n = 0;
  top: n + 1;
  put "f n=" n;
  if n < 3 then goto top;
  put "f exit n=" n;
run;

/* Index value after normal loop exit: ascending = stop+step, descending too. */
data _null_;
  do i = 1 to 3;
  end;
  do k = 10 to 2 by -3;
  end;
  put "g i=" i " k=" k;
run;
