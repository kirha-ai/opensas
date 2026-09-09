/* GAP-gapsexitingone §5b re-verdict — a TYPO'd PICTURE option (`filll`)
   is the USER's error, exit 1. The per-entry picture option list is
   closed by the doc, so the catch-all can tell a typo from an
   unimplemented option; the gap twin pins FILL= at rc 2. expect-rc: 1 */
proc format;
  picture p low-high='99' (filll='*');
run;
