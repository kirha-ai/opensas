/* BUG-hashremoveiter: Language Reference: Concepts p.621 Note — while an associated hash iterator is
   pointing to the key, REMOVE does NOT remove the key and issues an ERROR to
   the log (stderr here; the corpus pins stdout). opensas removed it anyway AND
   corrupted the cursor: this walk-and-delete loop visited k=1,3,5 and silently
   left 2 and 4 behind at exit 0. Now every remove fails rc=1, all five records
   are visited, and the hash keeps all five items.
   expect-rc: 1 */
data _null_;
  length k d 8;
  declare hash h(ordered:'y');
  h.defineKey('k'); h.defineData('k','d'); h.defineDone();
  do k=1 to 5; d=k*10; h.add(); end;
  declare hiter it('h');
  rc=it.first();
  do while (rc=0);
    put 'visit k=' k;
    junk=h.remove();
    put 'remove rc=' junk;
    rc=it.next();
  end;
  n=h.num_items;
  put 'left in hash=' n;
run;
/* The two controls (remove with NO iterator; remove with a declared but never-
   positioned iterator — both must still remove) live in the BUG-hashremoveiter
   exec.zig test: the p.621 ERRORs above trip the run-level errhalt after this
   step, so they cannot share this fixture. */
