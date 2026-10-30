/* GAP-opt-unknown-sweep: documented OPTIONS entries must not fall into the
   final typo arm. ERRORS= is log-throttling here, VNFERR is the default
   variable-not-found behavior, VALIDVARNAME=V6 is accepted here because the
   following step creates only <=8-byte names, and real SAS accepts unquoted
   MISSING=N.
   expect-rc: 0 */
options errors=1 vnferr validvarname=v6 missing=N;
data _null_;
  x = .;
  put "missing=" x;
run;
