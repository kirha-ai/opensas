/* BUG-picturepos1opts — FUZZ= before the value range specification is a
   documented SAS 9.4 PICTURE position-1 format-option ("The DEFAULT, FUZZ,
   MAX, MIN, MULTILABEL, NOTSORTED, and ROUND options are valid before the
   value range specification", Procedures Guide printed p. 1098) opensas
   does not honour — a recognized gap, exit 2. Was rc 1 with the degenerate
   `unsupported PICTURE entry ''`. Typo twin:
   rc_format_picture_pos1_typo.sas. expect-rc: 2 */
proc format;
  picture p (fuzz=0.1) low-high='99';
run;
