/* BUG-calloutuninit: the pure-OUTPUT arg of CALL CATS/CATT/CATX/VNAME/RAN* is
   written BY the routine — SAS emits NO `Variable X is uninitialized` NOTE for
   it (the NOTE goes to stderr, not this stdout diff; the exec.zig test block
   pins its absence). Pin the resulting values so a silent-drop regression
   shows up. */
data _null_;
  seed = 42;
  call cats(c1, 'a', 'b', 'c');
  call catt(c2, 'x ', 'y');
  call catx('-', c3, 'p', 'q');
  call vname(seed, nm);
  call ranuni(seed, u);
  put "c1=" c1 " c2=" c2 " c3=" c3 " nm=" nm " u=" u;
run;
