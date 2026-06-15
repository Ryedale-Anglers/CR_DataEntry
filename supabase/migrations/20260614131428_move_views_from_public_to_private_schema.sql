drop view public.table_indexes_non_pk;
CREATE OR REPLACE VIEW private.table_indexes_non_pk
AS SELECT schemaname AS schema_name,
    tablename AS table_name,
    indexname AS index_name,
    indexdef AS index_definition
   FROM pg_indexes
  WHERE schemaname = 'public'::name AND NOT (indexname IN ( SELECT pg_constraint.conname
           FROM pg_constraint
          WHERE pg_constraint.contype = 'p'::"char"))
  ORDER BY tablename, indexname;

drop view public.table_policies_overview;
CREATE OR REPLACE VIEW private.table_policies_overview
AS SELECT schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
   FROM pg_policies
  ORDER BY tablename; 

drop view public.table_rls_overview;
CREATE OR REPLACE VIEW private.table_rls_overview
AS SELECT pg_class.relname AS table_name,
        CASE
            WHEN pg_class.relrowsecurity = true THEN '✅ ENABLED (Locked)'::text
            ELSE '⚠️ DISABLED (Open)'::text
        END AS rls_status
   FROM pg_class
     JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
  WHERE pg_namespace.nspname = 'public'::name AND pg_class.relkind = 'r'::"char"
  ORDER BY pg_class.relname;
