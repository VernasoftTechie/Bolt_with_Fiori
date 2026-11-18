sap.ui.define([], function () {
  "use strict";

  var AGE_WARN_HOURS = 48;   // same thresholds as Bolt Console's AgeBadge
  var AGE_RISK_HOURS = 120;

  function escapeHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function inline(s) {
    return escapeHtml(s)
      .replace(/`([^`]+)`/g, "<code>$1</code>")
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/(^|[^*])\*([^*]+)\*(?!\*)/g, "$1<em>$2</em>");
  }

  /** Parses an ABAP timestamp (number like 20261118104200.1234567) or an ISO string. */
  function toDate(v) {
    if (v === null || v === undefined || v === "" || v === 0 || v === "0") { return null; }
    if (typeof v === "string" && v.indexOf("T") > 0) { return new Date(v); }
    var s = String(v).split(".")[0].padStart(14, "0");
    if (s === "00000000000000") { return null; }
    return new Date(Date.UTC(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8), +s.slice(8, 10), +s.slice(10, 12), +s.slice(12, 14)));
  }

  var formatter = {
    toDate: toDate,

    /** Small, safe Markdown -> HTML for sap.m.FormattedText (status file entries are Markdown). */
    markdown: function (sText) {
      if (!sText) { return ""; }
      var aOut = [];
      var sList = null;
      var closeList = function () { if (sList) { aOut.push("</" + sList + ">"); sList = null; } };
      String(sText).split(/\r?\n/).forEach(function (sLine) {
        var mBullet = /^\s*[-*]\s+(.*)$/.exec(sLine);
        var mNumber = /^\s*\d+\.\s+(.*)$/.exec(sLine);
        var mHead = /^\s*#{1,6}\s+(.*)$/.exec(sLine);
        if (mBullet || mNumber) {
          var sWant = mBullet ? "ul" : "ol";
          if (sList !== sWant) { closeList(); aOut.push("<" + sWant + ">"); sList = sWant; }
          aOut.push("<li>" + inline((mBullet || mNumber)[1]) + "</li>");
        } else if (mHead) {
          closeList();
          aOut.push("<p><strong>" + inline(mHead[1]) + "</strong></p>");
        } else if (!sLine.trim()) {
          closeList();
        } else {
          closeList();
          aOut.push("<p>" + inline(sLine) + "</p>");
        }
      });
      closeList();
      return aOut.join("");
    },

    dateTime: function (v) {
      var d = toDate(v);
      return d ? d.toLocaleString([], { dateStyle: "medium", timeStyle: "short" }) : "";
    },

    yyyymmdd: function (s) {
      if (!s || s.length !== 8 || s === "00000000") { return ""; }
      return new Date(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8)).toLocaleDateString([], { dateStyle: "medium" });
    },

    ageHours: function (oMig) {
      var dStart = toDate(oMig && oMig.CreatedAt);
      if (!dStart) { return null; }
      var bDone = oMig.Status === "completed";
      var dEnd = bDone ? (toDate(oMig.StatusUpdated) || new Date()) : new Date();
      return Math.max(0, (dEnd - dStart) / 3600000);
    },

    ageText: function (oMig) {
      var h = formatter.ageHours(oMig);
      if (h === null) { return ""; }
      if (h < 1) { return Math.round(h * 60) + " min"; }
      if (h < 48) { return Math.round(h) + " h"; }
      return Math.round(h / 24) + " d";
    },

    ageState: function (oMig) {
      var h = formatter.ageHours(oMig);
      if (h === null) { return "None"; }
      if (oMig.Status === "completed") { return "Success"; }
      if (h >= AGE_RISK_HOURS) { return "Error"; }
      if (h >= AGE_WARN_HOURS) { return "Warning"; }
      return "None";
    },

    /** One plain-language status for a migration row (send state first, then the status file). */
    statusText: function (oMig) {
      if (!oMig) { return ""; }
      if (oMig.Withdrawn === "X") { return "Withdrawn"; }
      if (oMig.PushStatus === "PENDING") { return "Sending to GitHub"; }
      if (oMig.PushStatus === "FAILED") { return "Sending failed"; }
      if (oMig.StopFlag === "X") { return "Stopped"; }
      return oMig.StatusLabel || "Queued";
    },

    statusState: function (oMig) {
      if (!oMig) { return "None"; }
      if (oMig.Withdrawn === "X") { return "None"; }
      if (oMig.PushStatus === "FAILED" || oMig.StopFlag === "X") { return "Error"; }
      if (oMig.PushStatus === "PENDING") { return "Information"; }
      if (oMig.Status === "completed" || oMig.Status === "interface_completed") { return "Success"; }
      if (formatter.needsClient(oMig)) { return "Warning"; }
      return "Information";
    },

    /** Waiting on someone other than the engineer, not stopped - the client has to act. */
    needsClient: function (oMig) {
      return !!(oMig && oMig.PushStatus === "PUSHED" && oMig.Withdrawn !== "X" && oMig.StopFlag !== "X" &&
        oMig.WaitingOn && oMig.WaitingOn !== "engineer");
    },

    waitingText: function (sWaiting) {
      if (!sWaiting) { return ""; }
      if (sWaiting === "operator" || sWaiting === "client") { return "You"; }
      if (sWaiting === "engineer") { return "Engineer"; }
      return sWaiting;
    },

    complexityState: function (s) {
      return { low: "Success", medium: "Warning", high: "Error" }[s] || "None";
    },

    complexityText: function (s) {
      return s ? s.charAt(0).toUpperCase() + s.slice(1) : "";
    },

    connectionState: function (s) {
      return s === "OK" ? "Success" : (s === "ERROR" ? "Error" : "None");
    },

    connectionText: function (s) {
      return s === "OK" ? "Connected" : (s === "ERROR" ? "Not connected" : "Not tested");
    },

    bytes: function (n) {
      if (!n) { return ""; }
      if (n < 1024) { return n + " B"; }
      if (n < 1048576) { return (n / 1024).toFixed(1) + " KB"; }
      return (n / 1048576).toFixed(1) + " MB";
    },

    branchExample: function (sPrefix) {
      var clean = function (s) {
        return String(s || "").trim().toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/-+/g, "-").replace(/^[-._]+|[-._]+$/g, "");
      };
      var p = clean(sPrefix);
      return (p ? p + "-" : "") + "zmm_po_form";
    },

    isX: function (v) { return v === "X" || v === true; }
  };

  return formatter;
});
