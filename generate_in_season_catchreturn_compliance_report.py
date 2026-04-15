from ast import Try

import pandas as pd
#import matplotlib.pyplot as plt 
import numpy as np
import os, glob
import typst


from sqlalchemy import create_engine, text
from dotenv import load_dotenv
from datetime import datetime

def setup():
    # Load environment variables (for your DB password/connection string)
    load_dotenv()

    # --- CONFIGURATION FROM ENV ---
    SUPABASE_CONN_STRING = os.getenv('CLOUD_DB_URL')
    LOCAL_RAC_REPORT_REPOSITORY_PATH = os.getenv('LOCAL_RAC_REPORT_REPOSITORY_PATH')

    if not SUPABASE_CONN_STRING :
        raise ValueError("Missing environment variable. Check your .env file.")
    
   
    # Connect to Supabase
    supabase_engine = create_engine(SUPABASE_CONN_STRING)

    print(f"Connecting to... {SUPABASE_CONN_STRING}")

    return supabase_engine, LOCAL_RAC_REPORT_REPOSITORY_PATH


def setup_front_page(conn):
    membership_year = conn.execute(text("SELECT target_year FROM year_param WHERE id = 1")).scalar()
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
    query = "select * from public.view_secrep_membername_catchreturns_count_operational"
    df_members = pd.read_sql_query(query, conn)

    # Clean names
    #df_members['cr_name'] = df_members['cr_name'].str.strip().str.title()

    total_reservations = df_members['num_booked'].sum()
    total_catch_returns = df_members['catch_returns'].sum()
    total_variance = df_members['variance'].sum()

    # 95: Add the total row
    df_members.loc[len(df_members)] = ['Total', total_reservations, total_catch_returns, total_variance]

    #Start the Typst Table String
    member_table_typst = """
    #text(weight: "bold", 1.2em, fill: blue)[Member Reservations v Catch Returns]
    #table(
    columns: (4.9cm, 1.6cm, 1.6cm, 1.6cm),
    inset: 6pt,
    align: (left, center, center, center),
    fill: (x, y) => if y == 0 { gray.lighten(80%) },
    stroke: 0.5pt + gray,
    table.header(
        [*Member Name*], [*Beats Booked*], [*Catch Returns*], [*Variance*]
    ),
    """

    # Populate rows
    for _, row in df_members.iterrows():
        # We use int() to ensure the total doesn't show as a float (e.g., 250.0)
        member_table_typst += f'  [{row["member_name"]}], [{int(row["num_booked"])}], [{int(row["catch_returns"])}], [{int(row["variance"])}],\n'

    member_table_typst += ")"
    # 4. Save to a separate file to keep the main script clean
    with open("member_submissions.typ", "w", encoding="utf-8") as f:
        f.write(member_table_typst)

    #Fetch the data for the Aged Debt Analysis section
    query_aged_debt = "SELECT * FROM view_missing_cr_age_report"
    df_aged_debt = pd.read_sql_query(query_aged_debt, conn)

    aged_debt_table_typst = """
    #text(weight: "bold", 1.2em, fill: blue)[Returns Missing by Age]
    #table(
    columns: (5cm, 2cm, 1.4cm, 1.4cm, 1.4cm, 1.4cm, 1.8cm),
    inset: 6pt,
    align: (left, center, center, center, center, center, center),
    fill: (x, y) => if y == 0 { gray.lighten(80%) },
    stroke: 0.5pt + gray,
    table.header(
        [*Member Name*], [*Returns Submitted*],[*8-14 Days*],[*15-21 Days*],[*21-28 Days*], [*28+ Days*], [*Total Missing*]
    ),
    """
    # Populate rows
    for _, row in df_aged_debt.iterrows():
        # We use int() to ensure the total doesn't show as a float (e.g., 250.0)
        aged_debt_table_typst += f'  [{row["member_name"]}], [{int(row["Returns Submitted"])}], [{int(row["8-14 Days"])}], [{int(row["15-21 Days"])}], [{int(row["21-28 Days"])}], [{int(row["28+ Days"])}],[{int(row["Total Missing"])}],\n'

    aged_debt_table_typst += ")"
    # 4. Save to a separate file to keep the main script clean
    with open("aged_debt_analysis.typ", "w", encoding="utf-8") as f:
        f.write(aged_debt_table_typst)

    final_report_content = f"""
    #pagebreak()
    #include "member_submissions.typ"
    #pagebreak()
    #include "aged_debt_analysis.typ"
     #text(weight: "regular", 1em, fill: blue)[-- End of Report --]
    """
    with open("sec_catch_report_operational_sections.typ", "w") as f:
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
        filename_str = f"{LOCAL_RAC_REPORT_REPOSITORY_PATH}inseason_catch_return_compliance_report_{timestamp}.pdf"
        typst.compile("sec_catch_report_operational_main.typ", output=filename_str)
        print("✅ Report PDF generated successfully!")

    except Exception as e:
        print(f"Error during PDF generation: {e}")  