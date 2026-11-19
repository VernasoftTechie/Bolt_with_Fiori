sap.ui.define([
  "vernasoft/boltfiori/controller/BaseController",
  "sap/ui/model/json/JSONModel",
  "sap/ui/model/Filter",
  "sap/ui/model/FilterOperator",
  "sap/ui/model/Sorter",
  "sap/m/MessageBox",
  "vernasoft/boltfiori/model/formatter",
  "vernasoft/boltfiori/model/service"
], function (BaseController, JSONModel, Filter, FilterOperator, Sorter, MessageBox, formatter, service) {
  "use strict";

  // StatusBoard.jsx NOTICES - word for word.
  var NOTICES = {
    confirm: "Confirmation submitted - the engineer has been notified and the migration is now In Progress.",
    problem: "Problem submitted - the engineer has been notified.",
    question: "Question submitted - the engineer has been notified.",
    change: "Change request submitted - the engineer has been notified.",
    concern: "Concern submitted - the engineer has been notified."
  };

  function blank() {
    return {
      busy: false, mig: {}, status: {}, timeline: [], hist: [], files: [],
      rowStatus: "", rowState: "None", stopped: false, superseded: false, disabled: false, needsConfirm: false,
      notice: "", error: "", text: "", msgFiles: [], hasMessage: false,
      stopNote: "", stopBusy: false, confirmBusy: false, busySend: false,
      docs: { list: [], add: [], dirty: false }, docsBusy: false,
      aiBusy: false, aiText: ""
    };
  }

  return BaseController.extend("vernasoft.boltfiori.controller.Detail", {

    onInit: function () {
      var oModel = new JSONModel(blank());
      this.getView().setModel(oModel, "det");
      this.router().getRoute("detail").attachPatternMatched(this._onMatched, this);
      this.enableDropZones();
      // "Send" buttons follow the text and the staged files (web: !text.trim() && !files.length).
      oModel.attachPropertyChange(this._derive, this);
    },

    _onMatched: function (oEvent) {
      this._sUuid = oEvent.getParameter("arguments").migUuid;
      this.getView().getModel("det").setData(blank());
      this.load();
    },

    onNavBack: function () {
      this.router().navTo("dashboard", { tab: "migration" }, true);
    },

    onRefresh: function () {
      var that = this;
      // Read the branch again (refreshStatus also stores the basic status), then show.
      this.withBusy(async function () {
        await that.service().action(service.migPath(that._sUuid), "refreshStatus", {});
        that.takeMessages();
        await that.load();
      }, "det", "/busy");
    },

    /** Reads the migration, its live status file + timeline, history and files. */
    load: async function () {
      var oDet = this.getView().getModel("det");
      var oService = this.service();
      var sPath = service.migPath(this._sUuid);
      oDet.setProperty("/busy", true);
      try {
        var aFilter = [new Filter("MigUuid", FilterOperator.EQ, this._sUuid)];
        var aResults = await Promise.all([
          oService.object(sPath),
          oService.list("/StatusFile", { filters: aFilter }),
          oService.list("/Timeline", { filters: aFilter, sorters: [new Sorter("EntryNo", true)] }),
          oService.list(sPath + "/_History", { sorters: [new Sorter("EventAt", true)] }),
          oService.list(sPath + "/_File", { sorters: [new Sorter("PushedAt", true)] })
        ]);
        var oMig = aResults[0] || {};
        var oStatus = aResults[1][0] || {};
        oDet.setProperty("/mig", oMig);
        oDet.setProperty("/status", Object.assign({}, oStatus, {
          Found: formatter.isX(oStatus.Found), StopRequested: formatter.isX(oStatus.StopRequested)
        }));
        oDet.setProperty("/timeline", aResults[2]);
        oDet.setProperty("/hist", aResults[3].map(function (o) { return Object.assign(o, { Stopped: formatter.isX(o.Stopped) }); }));
        var aFiles = aResults[4].map(function (o) { return Object.assign(o, { Removed: formatter.isX(o.Removed) }); });
        oDet.setProperty("/files", aFiles);
        // Legacy documents = every file of the migration still in the list (Workspace.jsx shows
        // the reference files and the attachments; removing only takes them off this list).
        oDet.setProperty("/docs", {
          list: aFiles.filter(function (o) { return !o.Removed && o.FileKind !== "STATUS"; })
            .map(function (o) { return Object.assign({}, o, { pendingRemove: false }); }),
          add: [], dirty: false
        });
        this._derive();
      } catch (oError) {
        oDet.setProperty("/error", this.errorOf(oError));
      } finally {
        oDet.setProperty("/busy", false);
      }
    },

    /** needsConfirm / disabled / stopped exactly as StatusBoard.jsx computes them. */
    _derive: function () {
      var oDet = this.getView().getModel("det");
      var oMig = oDet.getProperty("/mig") || {};
      var oStatus = oDet.getProperty("/status") || {};
      var bFound = !!oStatus.Found;
      var bDisabled = (bFound ? oStatus.MigStatus : oMig.MigStatus) === "completed";
      var bStopped = bFound ? !!oStatus.StopRequested : formatter.isX(oMig.Stopped);
      var sWaiting = bFound ? oStatus.WaitingOn : "";
      oDet.setProperty("/disabled", bDisabled);
      oDet.setProperty("/stopped", bStopped);
      oDet.setProperty("/superseded", formatter.isX(oMig.Superseded));
      oDet.setProperty("/needsConfirm", !!sWaiting && sWaiting !== "engineer" && !bStopped && !bDisabled);
      oDet.setProperty("/rowStatus", formatter.rowStatusText(oMig));
      oDet.setProperty("/rowState", formatter.rowStatusState(oMig));
      oDet.setProperty("/hasMessage", !!String(oDet.getProperty("/text") || "").trim() || (oDet.getProperty("/msgFiles") || []).length > 0);
      var oDocs = oDet.getProperty("/docs") || { list: [], add: [] };
      oDet.setProperty("/docs/dirty", (oDocs.add || []).length > 0 || (oDocs.list || []).some(function (o) { return o.pendingRemove; }));
    },

    /** Notices disappear after 8 seconds (StatusBoard.jsx). */
    _notice: function (sText) {
      var oDet = this.getView().getModel("det");
      oDet.setProperty("/notice", sText);
      clearTimeout(this._iNotice);
      this._iNotice = setTimeout(function () { oDet.setProperty("/notice", ""); }, 8000);
    },

    /** Runs one communication-panel action; the error is shown in the panel, not a popup. */
    _panelAction: async function (sFlag, fnWork) {
      var oDet = this.getView().getModel("det");
      oDet.setProperty(sFlag, true);
      oDet.setProperty("/error", "");
      try {
        await fnWork();
        this.takeMessages();
        await this.load();
        return true;
      } catch (oError) {
        oDet.setProperty("/error", this.errorOf(oError));
        return false;
      } finally {
        oDet.setProperty(sFlag, false);
      }
    },

    // ---- stop / resume ----

    onStop: function () {
      var that = this;
      var oDet = this.getView().getModel("det");
      this._panelAction("/stopBusy", async function () {
        await that.service().action(service.migPath(that._sUuid), "requestStop", { Reason: (oDet.getProperty("/stopNote") || "").trim() });
        oDet.setProperty("/stopNote", "");
      });
    },

    onResume: function () {
      var that = this;
      this._panelAction("/stopBusy", async function () {
        await that.service().action(service.migPath(that._sUuid), "resume", {});
      });
    },

    /** Stopped: the form can be selected again on the Smart Forms tab for a re-process run. */
    onReprocess: function () {
      var sForm = this.getView().getModel("det").getProperty("/mig/FormName");
      MessageBox.information(this.i18n("reprocessHow", [sForm]), {
        actions: [this.i18n("openSmartForms"), MessageBox.Action.CLOSE],
        onClose: function (sAction) {
          if (sAction === this.i18n("openSmartForms")) { this.router().navTo("dashboard", { tab: "forms" }); }
        }.bind(this)
      });
    },

    // ---- the response buttons and Raise a concern (one text + one file list) ----

    _respond: async function (sKind) {
      var that = this;
      var oDet = this.getView().getModel("det");
      var sFlag = sKind === "confirm" ? "/confirmBusy" : "/busySend";
      var bOk = await this._panelAction(sFlag, async function () {
        await that.service().action(service.migPath(that._sUuid), "respond", {
          Kind: sKind,
          Text: (oDet.getProperty("/text") || "").trim(),
          FilesJson: await that.filesJson(oDet.getProperty("/msgFiles"))
        });
      });
      if (bOk) {
        oDet.setProperty("/text", "");
        oDet.setProperty("/msgFiles", []);
        this._derive();
        this._notice(NOTICES[sKind] || NOTICES.concern);
      }
    },

    onConfirm: function () { this._respond("confirm"); },

    onSendKind: function (oEvent) { this._respond(oEvent.getSource().data("kind")); },

    onSendConcern: function () { this._respond("concern"); },

    onMsgFiles: function (oEvent) {
      this.stageFiles(oEvent.getParameter("files"), "det", "/msgFiles");
      oEvent.getSource().clear();
      this._derive();
    },

    onMsgUnstage: function (oEvent) {
      this.unstageFile(oEvent, "det", "/msgFiles");
      this._derive();
    },

    // ---- Legacy documents: stage adds and removals, then Save changes ----

    onDocsChosen: function (oEvent) {
      this.stageFiles(oEvent.getParameter("files"), "det", "/docs/add");
      oEvent.getSource().clear();
      this._derive();
    },

    onUnstageDoc: function (oEvent) {
      this.unstageFile(oEvent, "det", "/docs/add");
      this._derive();
    },

    onStageRemove: function (oEvent) {
      var oCtx = oEvent.getSource().getBindingContext("det");
      oCtx.getModel().setProperty(oCtx.getPath() + "/pendingRemove", true);
      this._derive();
    },

    onUndoRemove: function (oEvent) {
      var oCtx = oEvent.getSource().getBindingContext("det");
      oCtx.getModel().setProperty(oCtx.getPath() + "/pendingRemove", false);
      this._derive();
    },

    onSaveDocs: async function () {
      var that = this;
      var oDet = this.getView().getModel("det");
      var oDocs = oDet.getProperty("/docs");
      var aRemove = oDocs.list.filter(function (o) { return o.pendingRemove; }).map(function (o) {
        return String(o.FileUuid).replace(/-/g, "").toUpperCase();
      });
      await this.withBusy(async function () {
        await that.service().action(service.migPath(that._sUuid), "saveLegacyDocs", {
          FilesJson: await that.filesJson(oDocs.add),
          RemoveIds: aRemove.join(",")
        });
        that.showMessages();
        await that.load();
      }, "det", "/docsBusy");
    },

    // ---- send again / AI summary ----

    onSendAgain: function () {
      var that = this;
      this.withBusy(async function () {
        await that.service().action(service.migPath(that._sUuid), "pushToGitHub", {});
        that.showMessages();
        await that.load();
      }, "det", "/busy");
    },

    onAiSummary: function () {
      var that = this;
      var oDet = this.getView().getModel("det");
      this.withBusy(async function () {
        var oResult = await that.service().action(service.migPath(that._sUuid), "aiSummary", {});
        that.takeMessages();
        oDet.setProperty("/aiText", (oResult && oResult.Text) || "");
      }, "det", "/aiBusy");
    }
  });
});
