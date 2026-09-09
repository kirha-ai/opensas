/* PERF-fmtrangescan: INTERVAL-range user formats use a sorted-range binary
   search (O(log R) per lookup) instead of the full linear scan. Byte-identical
   gate: only provably non-overlapping ranges take the bsearch path (unique
   match == linear first-match). Pins adjacent + exclusion boundaries
   (`0-5`/`5<-10` split), low/high open ends, mixed discrete+range, OTHER,
   and a no-OTHER miss (raw render). Overlapping ranges are no longer a
   tie-break case: BUG-fmtoverlap makes them a PROC FORMAT error (SAS without
   MULTILABEL), so the linear fallback survives only as the index-OOM path. */
proc format;
  value adj 0-9="d0" 10-19="d1" 20-29="d2" other="oth";
  value exb 0-5="a" 5<-10="b" 10<-<15="c" other="oth";
  value hilo low-<0="neg" 0-high="pos";
  value mix 1="one" 10-20="teens" 25="twentyfive" other="oth";
  value nooth 20-<30="x";
run;
data _null_;
  do x = -1, 0, 9, 9.5, 10, 19, 20, 29, 30;
    y = put(x, adj.); put "adj " x= y=;
  end;
  do x = 0, 5, 7, 10, 12, 15;
    y = put(x, exb.); put "exb " x= y=;
  end;
  do x = -100, -0.5, 0, 100;
    y = put(x, hilo.); put "hilo " x= y=;
  end;
  do x = 1, 15, 25, 30;
    y = put(x, mix.); put "mix " x= y=;
  end;
  do x = 25, 99;
    y = put(x, nooth.); put "nooth " x= y=;
  end;
  m = .; y = put(m, adj.); put "adjmiss " y=;
run;
