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
