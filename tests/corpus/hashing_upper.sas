/* QA regression (BUG-hashinghex): SAS HASHING returns a message digest as an
   UPPERCASE hexadecimal string (doc p.975 example). hashing()/hashing_hmac()
   must match hashing_term() and the SAS-documented output. */
data _null_;
  m   = hashing('md5', 'The quick brown fox jumps over the lazy dog');
  s   = hashing('sha256', 'abc');
  hm  = hashing_hmac('SHA256', 'key', 'The quick brown fox jumps over the lazy dog');
  h   = hashing_init('md5'); rc = hashing_part(h, 'abc'); t = hashing_term(h);
  eq  = (hashing('md5','abc') = t);
  put "md5=" m;
  put "sha256=" s;
  put "hmac=" hm;
  put "term=" t;
  put "consistent=" eq;
run;
