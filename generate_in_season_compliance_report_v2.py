"""In-season catch return compliance report, version 2.

Based on generate_in_season_catchreturn_compliance_report.py. Uses
private.view_secrep_membername_catchreturns_count_operational_v2, which gives
each member's season reservations (1 April to yesterday) split by catch return
status: member return, guest only, DNF and missing.

Run with DB_TARGET=local or cloud (default cloud, as the original report).
Compiles sec_compliance_v2_main.typ into a PDF in LOCAL_RAC_REPORT_REPOSITORY_PATH.
"""
import os
from datetime import datetime

import pandas as pd
import typst
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

REPORT_TYPE = "SEC_OPER_V2"   # report_versions.report_type for this report's version history


def setup():
    load_dotenv()

    db_target = os.getenv('DB_TARGET', 'cloud').lower()
    if db_target not in ('local', 'cloud'):
        raise ValueError(f"DB_TARGET must be 'local' or 'cloud', got '{db_target}'")
    conn_string = os.getenv('CLOUD_DB_URL' if db_target == 'cloud' else 'LOCAL_DB_URL')
    if not conn_string:
        raise ValueError(f"Missing {'CLOUD_DB_URL' if db_target == 'cloud' else 'LOCAL_DB_URL'} environment variable. Check your .env file.")

    report_path = os.getenv('LOCAL_RAC_REPORT_REPOSITORY_PATH')
    if not report_path:
        raise ValueError("Missing LOCAL_RAC_REPORT_REPOSITORY_PATH environment variable. Check your .env file.")
    report_path = os.path.expanduser(report_path)
    os.makedirs(report_path, exist_ok=True)

    print(f"Connecting to {db_target.upper()} database...")
    return create_engine(conn_string), report_path


def typst_text(value):
    """Escape characters that Typst treats as markup inside [ ] content."""
    s = str(value)
    for ch in ('\\', '#', '[', ']', '*', '_', '$', '@', '<', '>', '`'):
        s = s.replace(ch, '\\' + ch)
    return s


def setup_front_page(conn):
    yp = conn.execute(text(
        "SELECT target_year, target_start_date, target_end_date FROM private.year_param WHERE id = 1")).one()
    season_year, season_start, season_end = yp
    # The status view covers the season up to yesterday.
    period_end = min(season_end, conn.execute(text("SELECT CURRENT_DATE - 1")).scalar())

    df_versions = pd.read_sql_query(
        text("""SELECT report_version, changes_txt, creation_date
                FROM report_versions
                WHERE report_year = :y AND report_type = :t
                ORDER BY report_version DESC"""),
        conn, params={"y": str(season_year), "t": REPORT_TYPE})
    latest_v = str(df_versions['report_version'].iloc[0]) if not df_versions.empty else "1.0"

    with open("report_settings_sec_compliance_v2.typ", "w", encoding="utf-8") as f:
        f.write(f'#let report_year = "{season_year}"\n')
        f.write(f'#let report_version = "{latest_v}"\n')
        f.write(f'#let period_start = "{season_start:%d %B %Y}"\n')
        f.write(f'#let period_end = "{period_end:%d %B %Y}"\n')

    version_table = """
    #table(
    columns: (auto, 1fr, auto),
    inset: 8pt,
    align: (center, left, center),
    fill: (x, y) => if y == 0 { gray.lighten(80%) },
    [*Version*], [*Changes*], [*Date*],
    """
    for _, row in df_versions.iterrows():
        version_table += (f'  [{typst_text(row["report_version"])}], [{typst_text(row["changes_txt"])}], '
                          f'[{row["creation_date"]}],\n')
    version_table += ")"
    with open("version_history_sec_compliance_v2.typ", "w", encoding="utf-8") as f:
        f.write(version_table)

    print(f"Front page set up for: Year {season_year}, Version {latest_v}, period to {period_end}")


def generate_member_status_table(conn):
    df = pd.read_sql_query(
        "SELECT * FROM private.view_secrep_membername_catchreturns_count_operational_v2", conn)

    count_cols = ['reservations_count', 'member_returns', 'guest_only', 'dnf', 'missing']
    totals = {c: int(df[c].sum()) for c in count_cols}

    table = """
    == Catch Return Status by Member
    For each member, a count of the catch return status of each reservation. A guest-only return is where only a 'guest' return was submitted. Missing is where no return has been submitted.
    The table is sorted by the number of missing returns, then by member name. 
    #set text(size: 0.8em)
    #table(
    columns: (4.2cm, 2.2cm, 2.2cm, 2.2cm, 2.2cm, 2.2cm),
    inset: 4pt,
    align: (left, center, center, center, center, center),
    fill: (x, y) => if y == 0 { gray.lighten(80%) },
    stroke: 0.5pt + gray,
    table.header(
        [*Member*], [*Reservations*], [*Member Returns*], [*Guest Only*], [*Did Not Fish*], [*Missing*]
    ),
    """
    for _, row in df.iterrows():
        cells = ", ".join(f"[{int(row[c])}]" for c in count_cols)
        table += f'  [{typst_text(row["cr_name"])}], {cells},\n'
    table += "  [*Total*], " + ", ".join(f"[*{totals[c]}*]" for c in count_cols) + ",\n"
    table += ")"

    with open("member_return_status.typ", "w", encoding="utf-8") as f:
        f.write(table)

    print(f"Member status table: {len(df)} members, {totals['reservations_count']} reservations, "
          f"{totals['missing']} missing")


def generate_members_no_reservations_table(conn):
    df = pd.read_sql_query(
        "SELECT member_name, cr_name, email_address FROM private.view_members_without_season_reservations_v2",
        conn)

    table = """
    == Members with No Reservations
    Members of the current season with no reservations from 1 April to 30 September, in surname order.
    #v(0.5em)
    #set text(size: 0.8em)
    #table(
    columns: (4.5cm, 3cm, 1fr),
    inset: 4pt,
    align: (left, left, left),
    fill: (x, y) => if y == 0 { gray.lighten(80%) },
    stroke: 0.5pt + gray,
    table.header(
        [*Member Name*], [*CR Name*], [*Email Address*]
    ),
    """
    for _, row in df.iterrows():
        cells = ", ".join(f"[{typst_text(row[c]) if pd.notna(row[c]) else ''}]"
                          for c in ('member_name', 'cr_name', 'email_address'))
        table += f'  {cells},\n'
    table += ")"

    with open("members_no_reservations_v2.typ", "w", encoding="utf-8") as f:
        f.write(table)

    print(f"Members with no reservations: {len(df)}")


def generate_report_sections(conn):
    generate_member_status_table(conn)
    generate_members_no_reservations_table(conn)

    sections = """
    #pagebreak()
    #include "member_return_status.typ"
    #v(1em)
    #include "members_no_reservations_v2.typ"
    #v(1em)
    #text(weight: "regular", 1em, fill: blue)[-- End of Report --]
    """
    with open("sec_compliance_v2_sections.typ", "w", encoding="utf-8") as f:
        f.write(sections)


if __name__ == "__main__":
    try:
        engine, report_path = setup()
        with engine.connect() as conn:
            setup_front_page(conn)
            generate_report_sections(conn)
        engine.dispose()

        print("Compiling the Typst document into PDF...")
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        filename = os.path.join(report_path, f"inseason_compliance_report_v2_{timestamp}.pdf")
        typst.compile("sec_compliance_v2_main.typ", output=filename)
        print(f"✅ Report PDF generated: {filename}")

    except Exception as e:
        print(f"Error during PDF generation: {e}")
        raise SystemExit(1)
