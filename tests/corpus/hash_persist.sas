data _null_;
  declare hash h();
  h.defineKey("k");
  h.defineData("v");
  h.defineDone();
  input k v cmd $;
  if cmd = "ADD" then rc = h.add();
  else do;
    rc = h.find();
    put "k=" k " v=" v;
  end;
  datalines;
1 100 ADD
2 200 ADD
1 . GET
2 . GET
;
run;
