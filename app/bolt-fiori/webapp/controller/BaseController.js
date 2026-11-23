sap.ui.define([
  "sap/ui/core/mvc/Controller",
  "sap/m/MessageToast",
  "sap/m/MessageBox",
  "vernasoft/boltfiori/model/formatter",
  "vernasoft/boltfiori/model/service"
], function (Controller, MessageToast, MessageBox, formatter, service) {
  "use strict";

  // Same picker rules as the web app's FilePicker.jsx (accept list), plus a size cap
  // so one upload stays well inside the gateway's request limit.
  var ACCEPT = ["png", "jpg", "jpeg", "gif", "bmp", "svg", "webp", "pdf", "doc", "docx", "txt", "log", "xml", "md"];
  var MAX_BYTES = 25 * 1024 * 1024;

  return Controller.extend("vernasoft.boltfiori.controller.BaseController", {
    formatter: formatter,

    service: function () {
      return this.getOwnerComponent().getService();
    },

    appModel: function () {
      return this.getOwnerComponent().getModel("app");
    },

    i18n: function (sKey, aArgs) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(sKey, aArgs);
    },

    router: function () {
      return this.getOwnerComponent().getRouter();
    },

    /** Runs fnWork with a busy flag set; shows the backend's message on failure. */
    withBusy: async function (fnWork, sModel, sPath) {
      var oModel = sModel ? this.getView().getModel(sModel) : this.appModel();
      var sFlag = sPath || "/busy";
      oModel.setProperty(sFlag, true);
      try {
        return await fnWork();
      } catch (oError) {
        this.showError(oError);
        return undefined;
      } finally {
        oModel.setProperty(sFlag, false);
      }
    },

    /** The backend's own error text (RAP messages first, then the HTTP error). */
    errorOf: function (oError) {
      var aMessages = this.service().drainMessages().filter(function (m) { return m.type === "Error"; });
      return aMessages.length ? aMessages.map(function (m) { return m.text; }).join("\n") : this.service().errorText(oError);
    },

    showError: function (oError) {
      // Wide and wrapping: SAP/GitHub texts contain long words (SSL codes, URLs) that
      // would otherwise be cut off - and the hint is at the end of the message.
      MessageBox.error(this.errorOf(oError), { contentWidth: "40rem", styleClass: "boltMsgWrap" });
    },

    /** Success/information/warning messages RAP returned with the last call. */
    takeMessages: function () {
      return this.service().drainMessages();
    },

    showMessages: function (sFallback) {
      var aMessages = this.takeMessages();
      var aWarnings = aMessages.filter(function (m) { return m.type === "Warning" || m.type === "Error"; });
      if (aWarnings.length) {
        MessageBox.warning(aWarnings.map(function (m) { return m.text; }).join("\n"), { contentWidth: "40rem", styleClass: "boltMsgWrap" });
        return;
      }
      var sText = aMessages.length ? aMessages.map(function (m) { return m.text; }).join("\n") : sFallback;
      if (sText) {
        MessageToast.show(sText, { duration: 5000, width: "30rem" });
      }
    },

    /**
     * The system the app runs in and the setup row (created on first start).
     * Readiness follows the web app: GitHub token connected, target repository
     * reachable with push access, AI provider ready (built-in, or a key saved).
     */
    loadContext: async function () {
      // The system info and the setup row are read independently: a problem with
      // one (e.g. the setup behaviour not active yet) never blanks the header or
      // the Smart Forms list - it is shown in a message strip instead.
      var oService = this.service();
      var oApp = this.appModel();
      var oSys = {};
      var oSetup = null;
      oApp.setProperty("/sysError", "");
      oApp.setProperty("/setupError", "");
      try {
        oSys = (await oService.list("/SystemInfo"))[0] || {};
      } catch (oError) {
        oApp.setProperty("/sysError", this.errorOf(oError));
      }
      oApp.setProperty("/sys", oSys);
      oApp.setProperty("/isAdmin", formatter.isX(oSys.IsAdmin));
      oApp.setProperty("/ready", {
        github: formatter.isX(oSys.GitHubReady),
        repo: formatter.isX(oSys.RepoReady),
        ai: formatter.isX(oSys.AiReady),
        all: formatter.isX(oSys.Live)
      });
      try {
        oSetup = await oService.action("/Setup", "initialize", {});
      } catch (oError) {
        oApp.setProperty("/setupError", this.errorOf(oError));
      }
      oApp.setProperty("/setup", oSetup || {});
      return oSetup;
    },

    // ---- file picker (FilePicker.jsx): stage several files, remove before sending ----

    /** FileUploader "change": adds the chosen files to the list at sModel>sPath. */
    stageFiles: function (aFiles, sModel, sPath) {
      var oModel = this.getView().getModel(sModel);
      var aStaged = (oModel.getProperty(sPath) || []).slice();
      var aRefused = [];
      Array.prototype.forEach.call(aFiles || [], function (oFile) {
        var sExt = String(oFile.name).split(".").pop().toLowerCase();
        if (sPath.indexOf("lib") < 0 && ACCEPT.indexOf(sExt) < 0 && !/^image\//.test(oFile.type)) {
          aRefused.push(oFile.name + " (type not accepted)");
          return;
        }
        if (oFile.size > MAX_BYTES) {
          aRefused.push(oFile.name + " (larger than 25 MB)");
          return;
        }
        aStaged.push({ name: oFile.name, size: oFile.size, file: oFile });
      });
      oModel.setProperty(sPath, aStaged);
      if (aRefused.length) {
        MessageToast.show(this.i18n("filesRefused", [aRefused.join(", ")]), { duration: 6000, width: "30rem" });
      }
    },

    unstageFile: function (oEvent, sModel, sPath) {
      var oItem = oEvent.getParameter("listItem") || oEvent.getSource();
      var iIndex = +oItem.getBindingContext(sModel).getPath().split("/").pop();
      var aStaged = (this.getView().getModel(sModel).getProperty(sPath) || []).slice();
      aStaged.splice(iIndex, 1);
      this.getView().getModel(sModel).setProperty(sPath, aStaged);
    },

    /**
     * Drag & drop of files from the PC (FilePicker.jsx: "drag & drop or choose")
     * onto any element marked with the custom data bolt-drop="<model>|<path>".
     * One delegated native listener on the view's root, so drop zones inside
     * fragments and re-rendered panels keep working.
     */
    enableDropZones: function () {
      var that = this;
      var oView = this.getView();
      var zoneOf = function (e) {
        return e.target && e.target.closest ? e.target.closest("[data-bolt-drop]") : null;
      };
      oView.addEventDelegate({
        onAfterRendering: function () {
          var oDom = oView.getDomRef();
          if (!oDom || oDom._boltDrop) { return; }
          oDom._boltDrop = true;
          oDom.addEventListener("dragover", function (e) {
            var oZone = zoneOf(e);
            if (!oZone) { return; }
            e.preventDefault();
            oZone.classList.add("boltDropActive");
          });
          oDom.addEventListener("dragleave", function (e) {
            var oZone = zoneOf(e);
            if (oZone) { oZone.classList.remove("boltDropActive"); }
          });
          oDom.addEventListener("drop", function (e) {
            var oZone = zoneOf(e);
            if (!oZone) { return; }
            e.preventDefault();
            oZone.classList.remove("boltDropActive");
            var aTarget = String(oZone.getAttribute("data-bolt-drop")).split("|");
            if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) {
              that.stageFiles(e.dataTransfer.files, aTarget[0], aTarget[1]);
            }
          });
        }
      });
    },

    /** The staged files as the FilesJson action parameter. */
    filesJson: async function (aStaged) {
      if (!aStaged || !aStaged.length) { return ""; }
      var aRead = await service.readFiles(aStaged.map(function (o) { return o.file; }));
      return JSON.stringify(aRead.map(function (o) { return { name: o.name, content: o.content }; }));
    },

    acceptList: function () { return ACCEPT.join(","); },

    /**
     * Keeps a page current while it is open: runs fnRefresh every 2 minutes while the route is shown
     * and the browser tab is visible, and at once when the tab becomes visible again after 2 minutes.
     * fnRefresh decides itself whether it may run now (nothing typed, staged or busy).
     */
    startAutoRefresh: function (sRoute, fnRefresh) {
      var that = this;
      var INTERVAL = 2 * 60 * 1000;
      this._iAutoLast = Date.now();
      var fnTick = function () {
        if (document.hidden || Date.now() - that._iAutoLast < INTERVAL - 1000) { return; }
        that._iAutoLast = Date.now();
        fnRefresh.call(that);
      };
      if (!this._bAutoWired) {
        this._bAutoWired = true;
        // Stop when another page is shown; the page's own route match starts it again.
        this.router().attachRouteMatched(function (oEvent) {
          if (oEvent.getParameter("name") !== sRoute) { that.stopAutoRefresh(); }
        });
        document.addEventListener("visibilitychange", function () {
          if (!document.hidden && that._iAutoTimer) { fnTick(); }
        });
      }
      this.stopAutoRefresh();
      this._iAutoTimer = setInterval(fnTick, 15000);
    },

    stopAutoRefresh: function () {
      if (this._iAutoTimer) { clearInterval(this._iAutoTimer); this._iAutoTimer = null; }
    }
  });
});
