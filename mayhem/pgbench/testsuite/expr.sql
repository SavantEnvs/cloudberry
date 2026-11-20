\set aid random(1, 100000 * :scale)
\set x abs(-3) + greatest(1,2) * 5 % 3
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
\sleep 1 ms
