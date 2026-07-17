create extension if not exists "hypopg" with schema "extensions";

create extension if not exists "index_advisor" with schema "extensions";

grant delete on table "private"."club_settings" to "anon";

grant insert on table "private"."club_settings" to "anon";

grant select on table "private"."club_settings" to "anon";

grant update on table "private"."club_settings" to "anon";

grant delete on table "private"."club_settings" to "authenticated";

grant insert on table "private"."club_settings" to "authenticated";

grant select on table "private"."club_settings" to "authenticated";

grant update on table "private"."club_settings" to "authenticated";

grant delete on table "public"."report_versions" to "anon";

grant insert on table "public"."report_versions" to "anon";

grant select on table "public"."report_versions" to "anon";

grant update on table "public"."report_versions" to "anon";

grant delete on table "public"."report_versions" to "authenticated";

grant insert on table "public"."report_versions" to "authenticated";

grant select on table "public"."report_versions" to "authenticated";

grant update on table "public"."report_versions" to "authenticated";

grant delete on table "public"."report_versions" to "service_role";

grant insert on table "public"."report_versions" to "service_role";

grant select on table "public"."report_versions" to "service_role";

grant update on table "public"."report_versions" to "service_role";


