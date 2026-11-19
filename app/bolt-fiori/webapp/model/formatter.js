sap.ui.define([], function () {
  "use strict";

  var AGE_WARN_HOURS = 48;   // same thresholds as Bolt Console's AgeBadge
  var AGE_RISK_HOURS = 120;

  // statusParse.js STATUS_LABELS - the branch status file's STATUS values.
  var STATUS_LABELS = {
    queued: "Queued",
    in_progress: "In Progress",
    interface_completed: "Interface Completed",
    waiting_manual: "Waiting — Manual Activity",
    layout_in_progress: "Form Design In Progress",
    completed: "Migration Completed",
    open_for_concerns: "Open — Awaiting Review",
    draft: "Draft - not on GitHub yet"
  };
  // StatusBoard.jsx STATUS_CLASS: complete = green, everything else pending.
  var COMPLETE = { interface_completed: true, completed: true };

  var EVENTS = {
    COMMITTED: "Selected for migration", PUSHED: "Sent to GitHub", PUSH_FAILED: "Sending to GitHub failed",
    STATUS: "Status changed on the branch", CONFIRMED: "Manual activity confirmed", PROBLEM: "Problem reported",
    QUESTION: "Question asked", CHANGE: "Change requested", CONCERN: "Concern raised", STOPPED: "Stop requested",
    RESUMED: "Resumed", DOCS_ADDED: "Legacy documents added", DOCS_REMOVED: "Legacy documents removed from the list",
    REPROCESSED: "Replaced by a re-process run"
  };
  var KINDS = {
    SNAPSHOT: "Legacy grab", XML: "Smart Form XML", STYLE: "Smart Style", DRIVER: "Driver source",
    STATUS: "Status file", LEGACY: "Legacy document", ATTACH: "Attachment"
  };

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

  function isX(v) { return v === "X" || v === true; }

  /** Parses an ABAP timestamp (number like 20261118104200.1234567), an Edm.DateTimeOffset or ISO string. */
  function toDate(v) {
    if (v === null || v === undefined || v === "" || v === 0 || v === "0") { return null; }
    if (typeof v === "string" && v.indexOf("T") > 0) { return new Date(v); }
    var s = String(v).split(".")[0].padStart(14, "0");
    if (s === "00000000000000") { return null; }
    return new Date(Date.UTC(+s.slice(0, 4), +s.slice(4, 6) - 1, +s.slice(6, 8), +s.slice(8, 10), +s.slice(10, 12), +s.slice(12, 14)));
  }

  var formatter = {
    toDate: toDate,
    isX: isX,
    STATUS_LABELS: STATUS_LABELS,

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

    /** Edm.Date "2026-11-18" or ABAP "20261118". */
    date: function (s) {
      if (!s || s === "00000000" || s === "0000-00-00") { return ""; }
      var c = String(s).replace(/-/g, "");
      if (c.length !== 8) { return String(s); }
      return new Date(+c.slice(0, 4), +c.slice(4, 6) - 1, +c.slice(6, 8)).toLocaleDateString([], { dateStyle: "medium" });
    },

    statusLabel: function (sStatus) {
      if (!sStatus) { return "Unknown"; }
      return STATUS_LABELS[sStatus] || sStatus;
    },

    /** Badge colour of a status file status (StatusBoard.jsx: complete = green, else pending). */
    statusBadgeState: function (sStatus) {
      return COMPLETE[sStatus] ? "Success" : "Warning";
    },

    isCompleted: function (oMig) { return !!oMig && oMig.MigStatus === "completed"; },

    ageHours: function (oMig) {
      var dStart = toDate(oMig && oMig.CreatedAt);
      if (!dStart) { return null; }
      var bDone = oMig.MigStatus === "completed";
      var dEnd = bDone ? (toDate(oMig.CompletedAt) || toDate(oMig.StatusUpdated) || new Date()) : new Date();
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
      if (oMig.MigStatus === "completed") { return "Success"; }
      if (h >= AGE_RISK_HOURS) { return "Error"; }
      if (h >= AGE_WARN_HOURS) { return "Warning"; }
      return "None";
    },

    /** One plain-language status for a migration row (send state first, then the status file). */
    rowStatusText: function (oMig) {
      if (!oMig) { return ""; }
      if (isX(oMig.Superseded)) { return "Replaced by a re-process run"; }
      if (oMig.PushStatus === "PENDING") { return isX(oMig.Stopped) ? "Draft discarded" : "Draft - not on GitHub yet"; }
      if (oMig.PushStatus === "FAILED") { return isX(oMig.Stopped) ? "Draft discarded" : "Draft - sending failed"; }
      if (isX(oMig.Stopped)) { return "Stopped"; }
      return formatter.statusLabel(oMig.MigStatus || "queued");
    },

    rowStatusState: function (oMig) {
      if (!oMig) { return "None"; }
      if (isX(oMig.Superseded)) { return "None"; }
      if (oMig.PushStatus === "FAILED" || isX(oMig.Stopped)) { return "Error"; }
      if (oMig.PushStatus === "PENDING") { return "Information"; }
      if (COMPLETE[oMig.MigStatus]) { return "Success"; }
      if (formatter.needsClient(oMig)) { return "Warning"; }
      return "Information";
    },

    /** Waiting on someone other than the engineer, not stopped - the client has to act. */
    needsClient: function (oMig) {
      return !!(oMig && oMig.PushStatus === "PUSHED" && !isX(oMig.Superseded) && !isX(oMig.Stopped) &&
        oMig.WaitingOn && oMig.WaitingOn !== "engineer");
    },

    /**
     * Migration category: draft = committed, initial load not on GitHub yet
     * (Drafts tab); otherwise the filters of the Migrations tab.
     */
    category: function (oMig) {
      if (isX(oMig.Superseded)) { return "replaced"; }
      if (oMig.MigStatus === "completed" && oMig.PushStatus === "PUSHED") { return "completed"; }
      if (isX(oMig.Stopped)) { return "stopped"; }
      if (oMig.PushStatus !== "PUSHED") { return "draft"; }
      return "active";
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

    /** Smart Forms tab: the migration column of a form. */
    formStateText: function (sState, iSerial, sStatus, iRun) {
      switch (sState) {
        case "ACTIVE": return "No. " + iSerial + " · " + formatter.statusLabel(sStatus) + (iRun > 1 ? " (run " + iRun + ")" : "");
        case "DRAFT": return "No. " + iSerial + " · draft";
        case "STOPPED": return "Stopped (No. " + iSerial + ") · can be re-processed";
        case "COMPLETED": return "Migrated (No. " + iSerial + ")";
        default: return "Available";
      }
    },

    formStateState: function (sState) {
      return { ACTIVE: "Information", STOPPED: "Warning", COMPLETED: "Success" }[sState] || "None";
    },

    eventText: function (s) { return EVENTS[s] || s || ""; },

    eventIcon: function (s) {
      return {
        COMMITTED: "sap-icon://add-document", PUSHED: "sap-icon://upload-to-cloud", PUSH_FAILED: "sap-icon://error",
        STATUS: "sap-icon://process", CONFIRMED: "sap-icon://accept", PROBLEM: "sap-icon://alert",
        QUESTION: "sap-icon://question-mark", CHANGE: "sap-icon://edit", CONCERN: "sap-icon://comment",
        STOPPED: "sap-icon://stop", RESUMED: "sap-icon://media-play", DOCS_ADDED: "sap-icon://attachment",
        DOCS_REMOVED: "sap-icon://delete", REPROCESSED: "sap-icon://refresh"
      }[s] || "sap-icon://circle-task";
    },

    actorText: function (s) {
      return { CLIENT: "Client", ENGINEER: "Engineer", SYSTEM: "Background job" }[s] || s || "";
    },

    kindText: function (s) { return KINDS[s] || s || ""; },

    connectionState: function (s) {
      return s === "OK" ? "Success" : (s === "ERROR" ? "Error" : "None");
    },

    bytes: function (n) {
      if (!n) { return ""; }
      if (n < 1024) { return n + " B"; }
      if (n < 1048576) { return (n / 1024).toFixed(1) + " KB"; }
      return (n / 1048576).toFixed(1) + " MB";
    },

    /** Same as migrationBranchName() in git.js - shown live under the prefix field. */
    branchExample: function (sPrefix) {
      var clean = function (s) {
        return String(s || "").trim().toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/-+/g, "-").replace(/^[-._]+|[-._]+$/g, "");
      };
      var p = clean(sPrefix);
      return (p ? p + "-" : "") + "zmm_po_form";
    },

    /** "1 file" / "3 files" */
    files: function (n) { return (n || 0) + (n === 1 ? " file" : " files"); }
  };

  return formatter;
});
