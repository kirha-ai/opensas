/* Walk a hash's entries with a hash iterator (DECLARE HITER first/next) */
data _null_;
  length code 8; /* p.613: key/data vars must be declared outside the hash */
  length label $12;
  declare hash h();
  h.definekey("code");
  h.definedata("code", "label");
  h.definedone();
  h.add(key: 1, data: 1, data: "ACTIVE");
  h.add(key: 2, data: 2, data: "PLACEBO");
  h.add(key: 3, data: 3, data: "SCREENFAIL");
  declare hiter it("h");
  rc = it.first();
  do while (rc = 0);
    put "code=" code " label=" label;
    rc = it.next();
  end;
run;
