/* BUG-controlflownesting (doc-finder tick162): control transfers crossing an
   AST nesting boundary. LINK from inside a DO loop resumes at the statement
   after the call site (all iterations run); GOTO to a label nested in a DO
   group transfers instead of silently ending the step; top-level LINK/GOTO
   behaviour is unchanged. */
data _null_;
  do i = 1 to 3;
    link show;
    x = i * 10;
    put "after link: i=" i " x=" x;
  end;
  put "done";
  return;
  show: put "in show: i=" i;
  return;
run;

data _null_;
  flag = 1;
  if flag then do;
    link sub;
    put "after link in do";
  end;
  put "after if";
  return;
  sub: put "in sub";
  return;
run;

data _null_;
  do i = 1 to 3;
    if i = 2 then goto skip;
    put "before skip i=" i;
    skip: put "at skip i=" i;
  end;
  put "done2";
run;

/* control: everything top-level — must be byte-identical to before */
data _null_;
  a = 5;
  link double;
  put "after link a=" a;
  goto fin;
  double:
  a = a * 2;
  return;
  fin: put "at fin";
run;
