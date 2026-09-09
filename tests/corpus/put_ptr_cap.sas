/* BUG-putptroom (docs/findings/qa-findings-tick146.md): an oversized PUT
   pointer target (@n / +n / #n) used to allocate the entire pad/newline run —
   `put @2147483648 'x';` tried to emit ~2 GB of spaces, an effective hang /
   OOM under a memory limit. Now the parser fails loud beyond the 32767
   line-size ceiling — fast, with no stdout (expected .txt is empty; the run
   terminating at all is the test). Normal small pointers are locked by
   put_colptr.sas.
   expect-rc: 1 */
data _null_;
  put @2147483648 'x';
run;
