/* GAP-opt-unknown-sweep: documented OPTIONS entries must not fall into the
   final typo arm. ERRORS= is log-throttling here, VNFERR is the default
   variable-not-found behavior, VALIDVARNAME=V6 is a documented value accepted
   by opensas's fixed name superset, NOXWAIT/NOXSYNC are host X-command policy
   toggles inert under D-022, and real SAS accepts unquoted MISSING=N.
   expect-rc: 0 */
options errors=1 vnferr validvarname=v6 noxwait noxsync missing=N;
data _null_;
  x = .;
  put "missing=" x;
run;
