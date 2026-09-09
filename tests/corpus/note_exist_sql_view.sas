/* NOTE-existsqlview — premise-audit pin. The ticket (qa tick203, INFO)
   claimed: "EXIST doesn't recognize PROC SQL views".
   Verdict: VACUOUS — PROC SQL views cannot EXIST in this tree:
   'proc sql; create view v as select * from t; quit;' fails loud
   (rc=2, "UNSUPPORTED: PROC SQL: CREATE VIEW is not supported yet",
   GAP-sqladvanced; pinned by sql.zig's in-file test). So EXIST('v','VIEW')
   returning 0 is the CORRECT answer — v genuinely does not exist — and
   EXIST('t','VIEW')=0 for a data set t matches SAS (t is not a view).
   No reachable state makes EXIST wrong. Upgrade path if CREATE VIEW ever
   lands: the type-arg arm in functions.zig ("any non-DATA member type
   cannot exist -> 0") must learn views. Pinned below: the full answer
   matrix. */
data t; x=1; run;
data _null_;
  a = exist('t');          /* 1 — data set exists              */
  b = exist('t','data');   /* 1 — ... and it is DATA           */
  c = exist('t','view');   /* 0 — ... but it is not a VIEW     */
  d = exist('v');          /* 0 — no member named v            */
  e = exist('v','view');   /* 0 — ... and no view can exist    */
  put a= b= c= d= e=;
run;
