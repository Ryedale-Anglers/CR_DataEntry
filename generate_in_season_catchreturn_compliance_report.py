from ast import Try

import pandas as pd
import matplotlib.pyplot as plt 
import numpy as np
import os, glob
import typst
import sys

from sqlalchemy import create_engine, text
from dotenv import load_dotenv
from datetime import datetime

def setup():
    # Load environment variables (for your DB password/connection string)
    load_dotenv()

    # --- CONFIGURATION FROM ENV ---
    # DB_TARGET (local|cloud) is normally set by rac_reports.py; defaults to
    # cloud when run directly, since that's this script's long-standing
    # behaviour and the systemd/manual invocations rely on that default.
    db_target = os.getenv('DB_TARGET', 'cloud').lower()
    if db_target not in ('local', 'cloud'):
        raise ValueError(f"DB_TARGET must be 'local' or 'cloud', got '{db_target}'")
    SUPABASE_CONN_STRING = os.getenv('CLOUD_DB_URL' if db_target == 'cloud' else 'LOCAL_DB_URL')
    LOCAL_RAC_REPORT_REPOSITORY_PATH = os.getenv('LOCAL_RAC_REPORT_REPOSITORY_PATH')

    if not LOCAL_RAC_REPORT_REPOSITORY_PATH:
        raise ValueError("Missing LOCAL_RAC_REPORT_REPOSITORY_PATH environment variable. Check your .env file.")

    # Create the report output directory if it doesn't already exist
    LOCAL_RAC_REPORT_REPOSITORY_PATH = os.path.expanduser(LOCAL_RAC_REPORT_REPOSITORY_PATH)
    os.makedirs(LOCAL_RAC_REPORT_REPOSITORY_PATH, exist_ok=True)

    if not SUPABASE_CONN_STRING:
        raise ValueError(f"Missing {'CLOUD_DB_URL' if db_target == 'cloud' else 'LOCAL_DB_URL'} environment variable. Check your .env file.")

    # Connect to Supabase
    supabase_engine = create_engine(SUPABASE_CONN_STRING)

    print(f"Connecting to {db_target.upper()} database...")

    return supabase_engine, LOCAL_RAC_REPORT_REPOSITORY_PATH


def setup_front_page(conn):
    membership_year = conn.execute(text("SELECT target_year FROM private.year_param WHERE id = 1")).scalar()
    print(f"Database parameter set to {membership_year}. All views are now synchronized.")

    # 1.    Fetch full version history once
    #       Extract latest version for the Header/Settings file
    #       If the DB is empty, default to 1.0
    version_query = f"""
    SELECT report_version, changes_txt, creation_date 
    FROM report_versions 
    WHERE report_year = '{membership_year}' AND report_type = 'SEC_OPER'
    ORDER BY report_version DESC
    """
    df_versions = pd.read_sql_query(version_query, conn)
    latest_v = str(df_versions['report_version'].iloc[0]) if not df_versions.empty else "1.0"

    # 3. Write report_settings.typ (The single point of truth for Year/Version)
    with open("report_settings_sec_operational.typ", "w", encoding="utf-8") as f:
        f.write(f'#let report_year = "{membership_year}"\n')
        f.write(f'#let report_version = "{latest_v}"\n')
    # 4. Generate the Typst Table for the Title Page (Simplified for Tinymist compatibility)
    version_table_typst = """
    #table(
    columns: (auto, 1fr, auto),
    inset: 8pt,
    align: (center, left, center), 
    fill: (x, y) => if y == 0 { gray.lighten(80%) },
    [*Version*], [*Changes*], [*Date*],
    """

    for _, row in df_versions.iterrows():
        version_table_typst += f'  [{row["report_version"]}], [{row["changes_txt"]}], [{row["creation_date"]}],\n'

    version_table_typst += ")"

    # 5. Write out the table file
    with open("version_history_sec_oper.typ", "w", encoding="utf-8") as f:
        f.write(version_table_typst)

    print(f"Front Page setup complete for: Year {membership_year}, Version {latest_v}")

    return membership_year

# =================================================================
# 1. DATABASE & UTILITIES
# =================================================================


# None yet, but this is where they would go. For example, a helper function to 
# create sparklines or to format tables could be defined here and then called in the section where we build the final_report_content string.


# =================================================================
# 5. TYPST DOCUMENT CONSTRUCTION
# =================================================================
# (The final_report_content string building)

def generate_report_sections(conn):

    # 1. Fetch the data for the Member Catch Return Submissions section
    query = "select * from private.view_secrep_membername_catchreturns_count_operational"
    df_members = pd.read_sql_query(query, conn)

    total_reservations = df_members['reservations_count'].sum()
    total_catch_returns = df_members['returns_count'].sum()
    total_variance = df_members['variance'].sum()

    # Add the total row
    df_members.loc[len(df_members)] = ['Total', total_reservations, total_catch_returns, total_variance]

    # Start the Typst Table String
    member_table_typst = """
    #text(weight: "bold", 0.9em, fill: blue)[Member Reservations v Catch Returns]
    #set text(size: 0.8em)//sets the text size for the table below
    #table(
    columns: (4.1cm, 1.4cm, 1.4cm, 1.4cm),
    inset: 4pt,
    align: (left, center, center, center),
    fill: (x, y) => if y == 0 { gray.lighten(80%) },
    stroke: 0.5pt + gray,
    table.header(
        [*Member Name*], [*Beats Booked*], [*Catch Returns*], [*Variance*]
    ),
    """

    # Populate rows
    for _, row in df_members.iterrows():
        member_table_typst += f'  [{row["cr_name"]}], [{int(row["reservations_count"])}], [{int(row["returns_count"])}], [{int(row["variance"])}],\n'

    member_table_typst += ")"
    
    with open("member_submissions.typ", "w", encoding="utf-8") as f:
        f.write(member_table_typst)

    # =================================================================
    # AGED DEBT ANALYSIS SECTION (FIXED TO MATCH 10 COLUMNS)
    # =================================================================
    query_aged_debt = "SELECT * FROM private.view_missing_cr_age_report5"
    df_aged_debt = pd.read_sql_query(query_aged_debt, conn)

    # Typst Table - Configured with EXACTLY 10 column widths and headers
    aged_debt_table_typst = """
    #text(weight: "bold", 1.2em, fill: blue)[Returns Missing by Age]
    #set text(size: 0.8em)//sets the text size for the table below
    #table(
    columns: (4cm, 1.6cm, 1.6cm, 1.4cm, 1.8cm, 1.4cm, 1.4cm, 1.4cm, 1.4cm, 1.4cm),
    inset: 4pt,
    align: (left, center, center, center, center, center, center, center, center, center),
    fill: (x, y) => if y == 0 { gray.lighten(80%) },
    stroke: 0.5pt + gray,
    table.header(
        [*Member Name*], [*Beats Booked*], [*Catch Returns*], [*CRs Due*], [*% Compliance*], [*1-7 Days*], [*8-14 Days*], [*15-21 Days*], [*22-28 Days*], [*28+ Days*]
    ),
    """
    
    # Populate rows
    for _, row in df_aged_debt.iterrows():
        # Extracted directly using the exact column keys from your query dataset
        aged_debt_table_typst += f'  [{row["member_name"]}], [{int(row["Reservations"])}], [{int(row["Catch Returns"])}], [{int(row["CRs Due"])}], [{int(row["pct_compliance"])}\\%], [{int(row["1-7 Days"])}], [{int(row["8-14 Days"])}], [{int(row["15-21 Days"])}], [{int(row["22-28 Days"])}], [{int(row["28+ Days"])}],\n'
    
    # Close the table string OUTSIDE of the loop
    aged_debt_table_typst += ")"

    with open("aged_debt_analysis.typ", "w", encoding="utf-8") as f:
        f.write(aged_debt_table_typst)

    # =================================================================
    # MEMBERS WITH NO RESERVATIONS THIS SEASON SECTION
    # =================================================================
    query_no_reservations = "SELECT * FROM private.view_members_without_season_reservations"
    df_no_reservations = pd.read_sql_query(query_no_reservations, conn)

    no_reservations_typst = """
    #text(weight: "bold", 1.2em, fill: blue)[Members With No Reservations This Season]
    #set text(size: 0.8em)//sets the text size for the table below
    #table(
    columns: (1fr),
    inset: 4pt,
    align: (left),
    fill: (x, y) => if y == 0 { gray.lighten(80%) },
    stroke: 0.5pt + gray,
    table.header(
        [*Member Name*]
    ),
    """

    # Populate rows
    for _, row in df_no_reservations.iterrows():
        no_reservations_typst += f'  [{row["member_name"]}],\n'

    no_reservations_typst += ")"

    with open("members_no_reservations.typ", "w", encoding="utf-8") as f:
        f.write(no_reservations_typst)

    final_report_content = f"""
    #pagebreak()
    #include "aged_debt_analysis.typ"
    #pagebreak()
    #include "member_submissions.typ"
    #pagebreak()
    #include "members_no_reservations.typ"
    #text(weight: "regular", 1em, fill: blue)[-- End of Report --]
    """
    with open("sec_catch_report_operational_sections.typ", "w", encoding="utf-8") as f:
        f.write(final_report_content)


if __name__ == "__main__":
    try:
        supabase_engine, LOCAL_RAC_REPORT_REPOSITORY_PATH = setup()
        with supabase_engine.begin() as conn: 
            membership_year = setup_front_page(conn)
            generate_report_sections(conn)
            
        print(f"Report .typ files updated and database connection closed.")
        print(f"Compiling the Typst document into PDF...")

        # Get current date and time
        now = datetime.now()
        # Format it: Year-Month-Day_Hour-Minute-Second
        timestamp = now.strftime("%Y-%m-%d_%H-%M-%S")
        filename_str = os.path.join(LOCAL_RAC_REPORT_REPOSITORY_PATH, f"inseason_catch_return_compliance_report_{timestamp}.pdf")
        typst.compile("sec_catch_report_operational_main.typ", output=filename_str)
        print("✅ Report PDF generated successfully!")

    except Exception as e:
        print(f"Error during PDF generation: {e}")  