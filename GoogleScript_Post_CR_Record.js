function doPost(e) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  // Dynamically select sheet based on the URL parameter
  var dataSheet = ss.getSheetByName((e.parameter.version === "test") ? "TestReturns" : "CatchReturns");
  var memberSheet = ss.getSheetByName("Members");
  
  try {
    var p = e.parameter;
    var submittedName = (p.rodName || "").trim();

    // 1. Validate Sheet existence
    if (!dataSheet) {
       return ContentService.createTextOutput(JSON.stringify({"result":"error", "message":"Target sheet not found"}))
        .setMimeType(ContentService.MimeType.JSON);
    }

    // 2. Get all names from Column A
    var lastRow = memberSheet.getLastRow();
    if (lastRow === 0) {
       return ContentService.createTextOutput(JSON.stringify({"result":"error", "message":"Member list is empty"}))
        .setMimeType(ContentService.MimeType.JSON);
    }
    
    var validNames = memberSheet.getRange(1, 1, lastRow, 1).getValues().flat();
    
    // 3. Check if name exists (Fuzzy Match)
    var matchedName = null;
    
    for (var i = 0; i < validNames.length; i++) {
      var currentName = validNames[i] ? validNames[i].toString().trim() : "";
      if (currentName.toLowerCase() === submittedName.toLowerCase()) {
        matchedName = currentName; // Capture the EXACT spelling from your sheet
        break;
      }
    }

    if (!matchedName) {
      return ContentService.createTextOutput(JSON.stringify({
        "result":"error", 
        "message":"Name '" + submittedName + "' not found in Members list."
      })).setMimeType(ContentService.MimeType.JSON);
    }

    // 4. Append the row using the OFFICIAL name
    dataSheet.appendRow([
      new Date(),
      matchedName, // Use the version from the Members sheet
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