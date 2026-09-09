/* GAP-gapsexitingone §5b (342b8305) — the rc-1 twin of rc_freq_by_gap.sas:
   after the split of PROC FORMAT's VALUE-option arm, a TYPO'D option
   ((multilabl) — MULTILABEL/NOTSORTED are the only two valid SAS 9.4 VALUE
   options, both now rc-2 gaps) is still the USER's error, exit 1
   ("fix your SAS"). If someone re-tags the split's catch-all wholesale,
   this fixture reds.
   expect-rc: 1 */
proc format;
  value f (multilabl) 1='a';
run;
