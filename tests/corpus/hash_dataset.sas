data lookup;
  input id nm $;
  datalines;
1 Alice
2 Bob
3 Carol
;
run;

data keys;
  input id;
  datalines;
2
3
1
;
run;

/* Hash loaded from a dataset:, then looked up per SET row. */
data _null_;
  if _n_ = 1 then do;
    declare hash h(dataset: "lookup");
    h.defineKey("id");
    h.defineData("nm");
    h.defineDone();
  end;
  set keys;
  rc = h.find();
  put "id=" id " nm=" nm;
run;
