/* audit-tick: hash_attr_ref — h.item_size (approximate per-item bytes,
   Language Reference: Concepts p.623) alongside h.num_items, parenless attribute form. */
data d; k = 1; v = 2; run;
data _null_;
  declare hash h(dataset:'d');
  h.definekey('k'); h.definedata('v'); h.definedone();
  n = h.num_items; s = h.item_size;
  put n= s=;
run;
