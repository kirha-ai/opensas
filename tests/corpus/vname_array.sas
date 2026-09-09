/* GH#23 ISS-vnamearray: the V-meta family must resolve an ARRAY-ELEMENT arg at
   runtime (the parse-time rewrite only catches the bare `vfunc(NAME)` form).
   VNAME(ch[i]) -> the member variable's NAME; siblings VTYPE/VLENGTH too. */
data _null_;
  length a $ 4 b $ 10;
  array ch{*} a b;
  a = "x"; b = "y";
  do i = 1 to dim(ch);
    nm = vname(ch[i]);
    ty = vtype(ch[i]);
    ln = vlength(ch[i]);
    put "V" i "=" nm " T=" ty " L=" ln;
  end;
  /* plain bare-variable form must still work (parse-time path, no regression) */
  pn = vname(a);
  put "plain=" pn;
run;
