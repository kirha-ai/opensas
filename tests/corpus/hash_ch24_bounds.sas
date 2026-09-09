/* Language Reference: Concepts Ch.24 "Using DATA Step Component Objects" — the parts of the chapter
   verified conformant in the tick293 audit that nothing else pinned.

   1. p.615 (PDF 633) Example 1 VERBATIM: ADD twice then FIND('Homer') must
      assign d='Odyssey'. The chapter's first worked program.
   2. The FORWARD end of the hiter rc contract: next() past the LAST item
      returns non-zero and leaves the key/data variables UNCHANGED, and a
      following first() re-enters the walk. hash_iter_prev pins the BACKWARD
      end (prev before first); the forward end was untested.
   3. The EMPTY-hash rc contract: first()/last() are non-zero and leave the
      data variables untouched (the carried-value gotcha), find()/check()
      return 160038, num_items is 0.
   4. p.622 (PDF 640): output() writes ONLY the defineData variables — a key
      appears only when it is also named in defineData. Asserted here through
      num_items + the retrieved data rather than a second data set, so this
      fixture needs no PROC. */
data _null_;
  length d $20;
  length k $20;
  declare hash h();
  rc = h.defineKey('k');
  rc = h.defineData('d');
  rc = h.defineDone();
  k = 'Homer';  d = 'Odyssey'; rc = h.add();
  k = 'Joyce';  d = 'Ulysses'; rc = h.add();
  k = 'Homer';  d = '';
  rc = h.find();
  put 'p615 find rc=' rc;
  put 'p615 d=' d;
run;

/* forward end of the iterator contract */
data _null_;
  length k n8 8;
  declare hash h(ordered:'y');
  h.defineKey('k'); h.defineData('k','n8'); h.defineDone();
  k=1; n8=10; h.add();
  k=2; n8=20; h.add();
  declare hiter it('h');
  rc=it.first(); put 'first rc=' rc ' k=' k ' n8=' n8;
  rc=it.next();  put 'next  rc=' rc ' k=' k ' n8=' n8;
  rc=it.next();  put 'past-last rc=' rc ' k=' k ' n8=' n8;
  rc=it.next();  put 'past-last-again rc=' rc ' k=' k ' n8=' n8;
  rc=it.first(); put 'reenter rc=' rc ' k=' k ' n8=' n8;
run;

/* empty-hash rc contract: nothing is written over the live PDV values */
data _null_;
  length k v 8;
  declare hash h();
  h.defineKey('k'); h.defineData('k','v'); h.defineDone();
  declare hiter it('h');
  k=7; v=77;
  rc=it.first(); put 'empty first rc=' rc ' k=' k ' v=' v;
  rc=it.last();  put 'empty last  rc=' rc ' k=' k ' v=' v;
  rc=h.find();   put 'empty find  rc=' rc;
  rc=h.check();  put 'empty check rc=' rc;
  n=h.num_items; put 'empty num=' n;
run;
