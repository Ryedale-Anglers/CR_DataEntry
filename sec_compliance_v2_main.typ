// Main page for the in-season compliance report v2
// (generate_in_season_compliance_report_v2.py). The script writes the
// settings, version history and section files included below.
#import "report_settings_sec_compliance_v2.typ": report_year, report_version, period_start, period_end

#set page(
  paper: "a4",
  flipped: false,
  margin: (left: 2cm, right: 2cm, top: 1.8cm, bottom: 2.5cm),
  header: context {
    set text(8pt, gray)
    let current_page = counter(page).at(here()).first()
    let total_pages = counter(page).final().at(0)
    grid(
      columns: (1fr, 1fr),
      align(left)[Ryedale Anglers Club — In Season Catch Returns Compliance],
      align(right)[Page #current_page of #total_pages]
    )
    v(-0.5em)
    line(length: 100%, stroke: 0.5pt + gray)
  },
  footer: context {
    set text(8pt, gray)
    line(length: 100%, stroke: 0.5pt + gray)
    v(0.5em)
    grid(
      columns: (1fr, 1fr),
      align(left)[Season: #report_year],
      align(right)[V #report_version]
    )
  }
)

#set text(font: "libertinus serif", size: 11pt)

// Title Page
#align(center)[
  #v(2fr)
  #text(weight: "bold", 2.5em)[Ryedale Anglers Club]
  #v(1em)
  #text(weight: "bold", 1.8em)[In Season - Report to Secretary]
  #v(1em)
  #text(weight: "bold", 1.8em)[Catch Returns Compliance]
  #v(1em)
  #text(weight: "bold", 1.4em, fill: blue)[#report_year Trout Season]
  #v(3fr)
  #text(weight: "bold", size: 1.2em, fill: blue)[Period #period_start to #period_end]
]

#v(2em)
#align(center)[
  #block(width: 80%)[
    #set text(size: 9pt)
    #align(left)[*Version Control History*]
    #include "version_history_sec_compliance_v2.typ"
  ]
]

#show heading.where(level: 2): set block(above: 0.8em, below: 0.8em)

// The Data Sections
#include "sec_compliance_v2_sections.typ"
