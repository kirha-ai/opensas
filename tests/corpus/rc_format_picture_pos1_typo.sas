/* BUG-picturepos1opts — a name the doc does NOT put in the PICTURE
   position-1 format-options (printed p. 1098 closes that set at
   DEFAULT/FUZZ/MAX/MIN/MULTILABEL/NOTSORTED/ROUND) is the USER's error,
   exit 1, NAMED (was the degenerate empty-entry message). Gap twin:
   rc_format_picture_pos1_gap.sas. expect-rc: 1 */
proc format;
  picture p (fuzzy=0.1) low-high='99';
run;
