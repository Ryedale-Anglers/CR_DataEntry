


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."beats" (
    "id" integer NOT NULL,
    "beat" "text" NOT NULL,
    "beat_short" "text",
    "river_order" "text",
    "upper_lower" "text"
);


ALTER TABLE "public"."beats" OWNER TO "postgres";


ALTER TABLE "public"."beats" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."beats_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."catch_returns" (
    "ID" integer NOT NULL,
    "member_name" "text",
    "catch_date" "text",
    "brown_trout" integer,
    "brown_trout_killed" integer,
    "grayling" integer,
    "rainbow_trout" integer,
    "other_species" integer,
    "guest" "text",
    "beats_id" integer
);


ALTER TABLE "public"."catch_returns" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."catch_returns_staging_table" (
    "id" integer NOT NULL,
    "timestamp" "text",
    "rod_name" "text",
    "catch_date" "date",
    "beat" "text",
    "brown_trout_released" integer,
    "grayling" integer,
    "rainbow_trout" integer,
    "other_species" integer,
    "brown_trout_retained" integer,
    "guest" "text",
    "comments" "text"
);


ALTER TABLE "public"."catch_returns_staging_table" OWNER TO "postgres";


ALTER TABLE "public"."catch_returns_staging_table" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."catch_returns_staging_table_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."members" (
    "id" integer NOT NULL,
    "cr_name" "text",
    "email_address" "text",
    "member_name" "text",
    "year_of_membership" integer
);


ALTER TABLE "public"."members" OWNER TO "postgres";


ALTER TABLE "public"."members" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."members_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."catch_returns"
    ADD CONSTRAINT "CatchReturns_pkey" PRIMARY KEY ("ID");



ALTER TABLE ONLY "public"."beats"
    ADD CONSTRAINT "beats_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."catch_returns_staging_table"
    ADD CONSTRAINT "catch_returns_staging_table_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."members"
    ADD CONSTRAINT "members_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_catch_returns_beats_id" ON "public"."catch_returns" USING "btree" ("beats_id");



CREATE INDEX "members_cr_name_idx" ON "public"."members" USING "btree" ("cr_name");



CREATE INDEX "members_cr_name_lower_idx" ON "public"."members" USING "btree" ("lower"("cr_name"));



CREATE INDEX "members_year_of_membership_idx" ON "public"."members" USING "btree" ("year_of_membership");



CREATE POLICY "Enable read access for all users" ON "public"."catch_returns_staging_table" FOR SELECT USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."members" FOR SELECT USING (true);



ALTER TABLE "public"."beats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."catch_returns" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."catch_returns_staging_table" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."members" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";


















GRANT ALL ON TABLE "public"."beats" TO "anon";
GRANT ALL ON TABLE "public"."beats" TO "authenticated";
GRANT ALL ON TABLE "public"."beats" TO "service_role";



GRANT ALL ON SEQUENCE "public"."beats_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."beats_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."beats_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."catch_returns" TO "anon";
GRANT ALL ON TABLE "public"."catch_returns" TO "authenticated";
GRANT ALL ON TABLE "public"."catch_returns" TO "service_role";



GRANT ALL ON TABLE "public"."catch_returns_staging_table" TO "anon";
GRANT ALL ON TABLE "public"."catch_returns_staging_table" TO "authenticated";
GRANT ALL ON TABLE "public"."catch_returns_staging_table" TO "service_role";



GRANT ALL ON SEQUENCE "public"."catch_returns_staging_table_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."catch_returns_staging_table_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."catch_returns_staging_table_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."members" TO "anon";
GRANT ALL ON TABLE "public"."members" TO "authenticated";
GRANT ALL ON TABLE "public"."members" TO "service_role";



GRANT ALL ON SEQUENCE "public"."members_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."members_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."members_id_seq" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































drop extension if exists "pg_net";


