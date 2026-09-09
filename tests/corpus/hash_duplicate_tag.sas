/* BUG-hashduplicate: duplicate:'r' keeps the LAST added record. */
data _null_;
  declare hash h(duplicate:'r');
  h.defineKey('k'); h.defineData('v'); h.defineDone();
  k=1; v=111; h.add();
  k=1; v=999; h.add();
  k=1; rc=h.find();
  put 'replace v=' v; /* expect 999 */
run;

/* BUG-hashdefinetag: defineData(all:'y') defines every PDV var INCLUDING
   the keys (SAS semantics — BUG-hashdefinedataall), not a phantom variable
   literally named 'y'. find() still restores v/w; k is now data too. */
data _null_;
  declare hash h2();
  h2.defineKey('k'); h2.defineData(all:'y'); h2.defineDone();
  k=1; v=42; w=7; h2.add();
  k=1; v=.; w=.; rc=h2.find();
  put 'all v=' v ' w=' w; /* expect 42, 7 */
run;
