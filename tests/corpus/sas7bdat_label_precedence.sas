/* GAP-sas7bdatlabelsubheader PRECEDENCE, pinned where the two sources DISAGREE:
   prec.sas7bdat carries in-file variable labels (X->"File Label X",
   Y->"File Label Y"; hand-laid bytes at the real readstat offsets — the offset
   proof itself is non-circular, pinned by the te/hadley unit tests) and the
   sibling prec.labels sidecar disagrees on X ("Sidecar Label X"). The rule:
   the in-file label is the BASE layer, the sidecar WINS — it records the
   latest program state (LABEL statement / MODIFY), the file only what it
   shipped with. So CONTENTS must show X -> "Sidecar Label X" (sidecar) and
   Y -> "File Label Y" (in-file, sidecar silent). */
libname l "tests/corpus/includes/lblprec";
proc contents data=l.prec; run;
