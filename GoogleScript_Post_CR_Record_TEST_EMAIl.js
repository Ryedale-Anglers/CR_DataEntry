function doGet(e) {
  var action = e.parameter.action;
  
  if (action === "requestHistory") {
    return handleEmailRequest(e.parameter.rodName);
  }
  
  return ContentService.createTextOutput("Invalid Action");
}

function handleEmailRequest(submittedName) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var dataSheet = ss.getSheetByName("CatchReturns");
  var memberSheet = ss.getSheetByName("Members");
  var name = (submittedName || "").trim().toLowerCase();
  
  // 1. Find Member Email
  var memberData = memberSheet.getRange(1, 1, memberSheet.getLastRow(), 3).getValues();
  var userEmail = "";
  var officialName = "";
  var longerName = "";
  
  for (var i = 0; i < memberData.length; i++) {
    if (memberData[i][0].toString().toLowerCase() === name) {
      officialName = memberData[i][0];
      userEmail = memberData[i][1]; // Column B
      longerName = memberData[i][2] ? memberData[i][2].toString().trim() : officialName;
      break;
    }
  }
  
  if (!userEmail) {
    return ContentService.createTextOutput(JSON.stringify({"result":"error", "message":"Member or email not found."})).setMimeType(ContentService.MimeType.JSON);
  }

  // 2. Filter Catch Data
  // 2. Filter and Sort Catch Data
  var catchData = dataSheet.getDataRange().getValues();
  
  var history = catchData
    .filter(row => row[1].toString().toLowerCase() === name)
    .sort((a, b) => {
      // row[2] is the Date column
      // return new Date(a[2]) - new Date(b[2]); // Ascending (Oldest to Newest)
      return new Date(b[2]) - new Date(a[2]); // for Descending (Newest first)
    });
  
  if (history.length === 0) {
    return ContentService.createTextOutput(JSON.stringify({"result":"error", "message":"No catch records found for this name."})).setMimeType(ContentService.MimeType.JSON);
  }

  // 3. Create Email Body (HTML Table)
  // We add padding to the Date header and center the numeric headers
  var htmlTable = "<h2>Catch Returns for " + longerName + "</h2>" +
                  "<table border='1' style='border-collapse:collapse; font-family: Arial, sans-serif;'> " +
                  "<tr style='background-color: #f2f2f2;'>" +
                  "<th style='padding: 10px 20px 10px 10px; text-align: left;'> Date </th>" + // Padding-right: 20px
                  "<th style='padding: 10px;'> Beat </th>" +
                  "<th style='padding: 10px; text-align: center;'> BT Released </th>" +
                  "<th style='padding: 10px; text-align: center;'> Grayling </th>" +
                  "<th style='padding: 10px; text-align: center;'> Rainbow </th>" +
                  "<th style='padding: 10px; text-align: center;'> Other </th>" +
                  "<th style='padding: 10px; text-align: center;'> BT Killed </th>" +
                  "</tr>";
  
  history.forEach(row => {
    var formattedDate = Utilities.formatDate(new Date(row[2]), ss.getSpreadsheetTimeZone(), "yyyy-MM-dd");
    
    htmlTable += "<tr>" +
                 "<td style='padding: 8px 20px 8px 8px;'>" + formattedDate + "</td>" + // Padded Date
                 "<td style='padding: 8px;'>" + row[3] + "</td>" +                   // Normal Beat
                 "<td style='padding: 8px; text-align: center;'>" + row[4] + "</td>" + // Centered Numbers
                 "<td style='padding: 8px; text-align: center;'>" + row[5] + "</td>" +
                 "<td style='padding: 8px; text-align: center;'>" + row[6] + "</td>" +
                 "<td style='padding: 8px; text-align: center;'>" + row[7] + "</td>" +
                 "<td style='padding: 8px; text-align: center;'>" + row[8] + "</td>" +
                 "</tr>";
  });
  htmlTable += "</table>";

  // 4. Send Email with Professional Formatting
  MailApp.sendEmail({
    to: userEmail,
    subject: "Catch Return History: " + longerName,
    name: "Ryedale Anglers Club", // This changes the "From" display name
    htmlBody: `
      <div style="font-family: Arial, sans-serif; color: #333;">
        <h2 style="color: #1a365d; border-bottom: 2px solid #1a365d;">Ryedale Anglers Club</h2>
        <p>Hello ${longerName},</p>
        <p>As requested, here are your Catch Return Records:</p>
        ${htmlTable}
        <p style="margin-top: 20px; font-size: 0.8rem; color: #666;">
          This report was generated electronically from the Ryedale Anglers Catch Return Database
        </p>
      </div>
    `
  });

  return ContentService.createTextOutput(JSON.stringify({"result":"success", "message":"Catch Returns were sent to " + userEmail})).setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  // Since this is the Test Sheet, we go straight to CatchReturns
  var dataSheet = ss.getSheetByName("CatchReturns"); 
  var memberSheet = ss.getSheetByName("Members");
  
  try {
    var p = e.parameter;
    var submittedName = (p.rodName || "").trim();

    if (!dataSheet || !memberSheet) {
       return ContentService.createTextOutput(JSON.stringify({"result":"error", "message":"Sheets not found"}))
        .setMimeType(ContentService.MimeType.JSON);
    }

    var lastRow = memberSheet.getLastRow();
    var validNames = memberSheet.getRange(1, 1, lastRow, 1).getValues().flat();
    
    var matchedName = null;
    for (var i = 0; i < validNames.length; i++) {
      var currentName = validNames[i] ? validNames[i].toString().trim() : "";
      if (currentName.toLowerCase() === submittedName.toLowerCase()) {
        matchedName = currentName;
        break;
      }
    }

    if (!matchedName) {
      return ContentService.createTextOutput(JSON.stringify({
        "result":"error", 
        "message":"Name '" + submittedName + "' not found in Members list."
      })).setMimeType(ContentService.MimeType.JSON);
    }

    // Append to the test sheet
    dataSheet.appendRow([
      new Date(),
      matchedName,
      p.date,
      p.category,
      p.v1, p.v2, p.v3, p.v4, p.v5,
      p.verified ? "Yes" : "No",
      p.comments
    ]);
    
    return ContentService.createTextOutput(JSON.stringify({"result":"success"}))
      .setMimeType(ContentService.MimeType.JSON);

  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({"result":"error", "message": err.toString()}))
      .setMimeType(ContentService.MimeType.JSON);
  }
}
