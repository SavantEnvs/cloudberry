\set i random_exponential(1, 10, 2.5) + random_gaussian(1, 10, 2.5) + random_zipfian(1, 10, 1.5)
\set f debug(sqrt(2.0) * pi() / ln(10) + exp(1.0) - pow(2, 0.5))
\set b case when :i > 5 then true else false end
\if :b
  SELECT 1 \gset p_
\elif :i = 0
  \setshell x echo 3
\else
  \shell true
\endif
\set h hash(10, 5432) + hash_fnv1a(:i) + permute(:i, 100, 7)
\startpipeline
SELECT 1;
\endpipeline
