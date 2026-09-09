data _null_;
  length k 8 v $4;
  declare hash h();
  h.defineKey('k');
  h.defineData('v'); /* key k is NOT in defineData → must NOT appear in output */
  h.defineDone();
  k=2; v='two'; h.add();
  k=1; v='one'; h.add();
  h.output(dataset:'work.hk');
run;
data _null_;
  set work.hk;
  /* only v exists; k was the key and is absent, so k reads as missing */
  put "v=" v " k=" k;
run;
