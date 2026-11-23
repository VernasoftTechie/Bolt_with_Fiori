sap.ui.define([
  "vernasoft/boltfiori/controller/BaseController",
  "sap/ui/model/json/JSONModel",
  "sap/ui/core/Fragment",
  "sap/m/MessageBox",
  "sap/m/MessageToast",
  "vernasoft/boltfiori/model/formatter",
  "vernasoft/boltfiori/model/service",
  "sap/ui/model/Sorter"
], function (BaseController, JSONModel, Fragment, MessageBox, MessageToast, formatter, service, Sorter) {
  "use strict";

  var AI_LABEL = { openai: "OpenAI", anthropic: "Anthropic" };

  // The list shows the status stored in SAP; it is read from GitHub by "Read statuses", by the
  // job ZABR_BOLT_SYNC and - at most every 5 minutes - automatically when the dashboard opens.
  var AUTO_READ_MS = 5 * 60 * 1000;
  var iLastGitHubRead = 0;

  /**
   * The dashboard: the process on the left (1 Smart Forms, 2 Drafts, 3 Migrations),
   * Setup and Help on the right. Setup itself is its own page (Setup.controller.js).
   */
  return BaseController.extend("vernasoft.boltfiori.controller.Dashboard", {

    onInit: function () {
      this.getView().setModel(new JSONModel({
        tab: "forms",
        counts: {
          formsAll: 0, formsAvailable: 0, formsActive: 0, formsStopped: 0, formsCompleted: 0,
          drafts: 0, migAll: 0, needs: 0, active: 0, stopped: 0, completed: 0
        },
        forms: [], formsShown: [], formsBusy: false, formsError: "", search: "", formFilter: "all", selectedCount: 0,
        drafts: [], draftBusy: false,
        migrations: [], migrationsShown: [], migBusy: false, migSearch: "", migFilter: "all", showReplaced: false,
        lastRefreshText: "", aiText: "",
        commit: { items: [], committed: false, busy: false, done: false, asDrafts: false }
      }), "view");
      this.router().getRoute("dashboard").attachPatternMatched(this._onMatched, this);
    },

    _onMatched: function (oEvent) {
      var sTab = (oEvent.getParameter("arguments") || {}).tab;
      if (sTab === "migration") { sTab = "migrations"; } // links of version 2.0
      if (sTab) { this.getView().getModel("view").setProperty("/tab", sTab); }
      // Always current when coming back from a migration or from Setup.
      this.reload();
    },

    reload: async function () {
      await this.loadContext();
      this._sideTexts();
      await Promise.all([this.loadForms(), this.loadMigrations()]);
      this._autoReadStatuses();
    },

    /** Reads the open migrations from GitHub in the background when the last read is older than 5 minutes. */
    _autoReadStatuses: async function () {
      var oView = this.getView().getModel("view");
      var bOpen = (oView.getProperty("/migrations") || []).some(function (o) {
        return o.category === "active" || o.category === "stopped";
      });
      if (!bOpen || !this.appModel().getProperty("/ready/repo") || Date.now() - iLastGitHubRead < AUTO_READ_MS) { return; }
      iLastGitHubRead = Date.now();
      oView.setProperty("/migReading", true);
      try {
        await this.service().listAction("/Migration", "refreshAll", {});
        this.takeMessages();
        this._markGitHubRead();
        await this.loadMigrations();
      } catch (oError) {
        // Silent in the background: the label says so and "Read statuses" shows the reason.
        oView.setProperty("/lastRefreshText", this.i18n("lastRefreshFailed"));
      } finally {
        oView.setProperty("/migReading", false);
      }
    },

    _markGitHubRead: function () {
      iLastGitHubRead = Date.now();
      this.getView().getModel("view").setProperty("/lastRefreshText",
        this.i18n("lastRefresh", [new Date().toLocaleTimeString([], { timeStyle: "short" })]));
    },

    /** The AI line of the Setup panel (blue built-in / green tested provider / red). */
    _sideTexts: function () {
      var oSetup = this.appModel().getProperty("/setup") || {};
      var sProvider = oSetup.AiProvider || "mock";
      var sText;
      if (sProvider === "mock") {
        sText = this.i18n("aiBuiltinLine");
      } else if (!this.appModel().getProperty("/ready/ai")) {
        sText = AI_LABEL[sProvider] + " · " + this.i18n("needsKey");
      } else {
        sText = AI_LABEL[sProvider] + " · " + (oSetup.AiCheckRes === "ERROR" ? this.i18n("testFailed") : (oSetup.AiModel || this.i18n("ready")));
      }
      this.getView().getModel("view").setProperty("/aiText", sText);
    },

    // ================================ header / side panel ================================

    onRefreshAll: function () { this.reload(); },

    onOpenSetup: function () { this.router().navTo("setup"); },

    onOpenHelp: function () { this.router().navTo("help", { section: "process" }); },

    onTabSelect: function (oEvent) {
      this.router().navTo("dashboard", { tab: oEvent.getParameter("key") }, true);
    },

    // ================================ 1. Smart Forms ================================

    loadForms: async function () {
      var oView = this.getView().getModel("view");
      oView.setProperty("/formsBusy", true);
      oView.setProperty("/formsError", "");
      try {
        var aForms = await this.service().list("/SmartForm");
        aForms.forEach(function (o) { o.selected = false; o.Selectable = formatter.isX(o.Selectable); });
        oView.setProperty("/forms", aForms);
        oView.setProperty("/counts/formsAll", aForms.length);
        oView.setProperty("/counts/formsAvailable", aForms.filter(function (o) { return o.Selectable; }).length);
        ["ACTIVE", "STOPPED", "COMPLETED"].forEach(function (sState) {
          oView.setProperty("/counts/forms" + sState.charAt(0) + sState.slice(1).toLowerCase(),
            aForms.filter(function (o) { return o.MigState === sState; }).length);
        });
      } catch (oError) {
        oView.setProperty("/forms", []);
        oView.setProperty("/formsError", this.errorOf(oError));
      } finally {
        oView.setProperty("/formsBusy", false);
      }
      this.applyFormFilter();
    },

    applyFormFilter: function () {
      var oView = this.getView().getModel("view");
      var sSearch = (oView.getProperty("/search") || "").trim().toLowerCase();
      var sFilter = oView.getProperty("/formFilter");
      var aShown = (oView.getProperty("/forms") || []).filter(function (o) {
        if (sFilter === "available" && !o.Selectable) { return false; }
        if (sFilter !== "all" && sFilter !== "available" && o.MigState !== sFilter) { return false; }
        if (!sSearch) { return true; }
        return [o.FormName, o.Description, o.DevPackage, o.DriverProgs, o.OutputTypes].some(function (s) {
          return String(s || "").toLowerCase().indexOf(sSearch) >= 0;
        });
      });
      oView.setProperty("/formsShown", aShown);
      this._countSelected();
    },

    onFormSearch: function () { this.applyFormFilter(); },
    onFormFilter: function () { this.applyFormFilter(); },

    _countSelected: function () {
      var oView = this.getView().getModel("view");
      oView.setProperty("/selectedCount", (oView.getProperty("/forms") || []).filter(function (o) { return o.selected; }).length);
    },

    /**
     * A form in migration or completed cannot be selected again (one active branch
     * per form). One refused form is named; several (e.g. "select all") are counted.
     */
    onFormSelect: function (oEvent) {
      var aRefused = [];
      var aItems = oEvent.getParameter("listItems") || [oEvent.getParameter("listItem")];
      aItems.forEach(function (oItem) {
        var oCtx = oItem && oItem.getBindingContext("view");
        if (!oCtx) { return; }
        var oForm = oCtx.getObject();
        if (oItem.getSelected() && !oForm.Selectable) {
          oCtx.getModel().setProperty(oCtx.getPath() + "/selected", false);
          aRefused.push(oForm);
        }
      });
      if (aRefused.length === 1) {
        MessageToast.show(aRefused[0].FormName + this.i18n(aRefused[0].MigState === "COMPLETED" ? "refusedCompleted" : "refusedActive"),
          { duration: 4000, width: "28rem" });
      } else if (aRefused.length > 1) {
        MessageToast.show(this.i18n("refusedMany", [aRefused.length]), { duration: 5000, width: "28rem" });
      }
      this._countSelected();
    },

    onOpenMigrationFromForm: function (oEvent) {
      var oForm = oEvent.getSource().getBindingContext("view").getObject();
      if (oForm.LastMigUuid) {
        this.router().navTo("detail", { migUuid: oForm.LastMigUuid });
      }
    },

    onExportForms: function () {
      var aCols = [
        { label: this.i18n("colForm"), property: "FormName" },
        { label: this.i18n("colDescription"), property: "Description" },
        { label: this.i18n("colPackage"), property: "DevPackage" },
        { label: this.i18n("colDriver"), property: "DriverProgs" },
        { label: this.i18n("colOutputTypes"), property: "OutputTypes" },
        { label: this.i18n("colChangedBy"), property: "ChangedBy" },
        { label: this.i18n("colChanged"), property: "ChangedOn" },
        { label: this.i18n("colMigration"), property: "stateText" }
      ];
      var aRows = this.getView().getModel("view").getProperty("/formsShown").map(function (o) {
        return Object.assign({}, o, { stateText: formatter.formStateText(o.MigState, o.LastSerialNo, o.LastStatus, o.LastRunNo) });
      });
      this._export(aCols, aRows, "SmartForms_" + (this.appModel().getProperty("/sys/SystemId") || ""));
    },

    // ---- Next > confirmation > Commit > automatic transfer (or drafts) ----

    onNext: async function () {
      var oView = this.getView().getModel("view");
      var aSelected = (oView.getProperty("/forms") || []).filter(function (o) { return o.selected && o.Selectable; });
      if (!aSelected.length) { return; }
      var that = this;
      oView.setProperty("/commit", {
        committed: false, busy: false, done: false,
        // GitHub not ready: commit anyway, the forms wait as drafts (no failing sends).
        asDrafts: !this.appModel().getProperty("/ready/repo"),
        items: aSelected.map(function (o) {
          return {
            FormName: o.FormName, Description: o.Description, state: "None", icon: "sap-icon://document",
            text: o.MigState === "STOPPED" ? that.i18n("reprocessRun", [(o.LastRunNo || 0) + 1]) : ""
          };
        })
      });
      if (!this._oCommitDialog) {
        this._oCommitDialog = await Fragment.load({
          id: this.getView().getId(), name: "vernasoft.boltfiori.fragment.CommitDialog", controller: this
        });
        this.getView().addDependent(this._oCommitDialog);
      }
      this._oCommitDialog.open();
    },

    onCommit: async function () {
      var that = this;
      var oView = this.getView().getModel("view");
      var aItems = oView.getProperty("/commit/items");
      var bDrafts = oView.getProperty("/commit/asDrafts");
      oView.setProperty("/commit/busy", true);
      var aCreated;
      try {
        aCreated = await this.service().listAction("/Migration", "commitSelection", {
          FormNames: aItems.map(function (o) { return o.FormName; }).join(",")
        });
      } catch (oError) {
        oView.setProperty("/commit/busy", false);
        this.showError(oError);
        return;
      }
      var aMessages = this.takeMessages();
      oView.setProperty("/commit/committed", true);

      // Forms skipped by the backend (another user committed them meanwhile).
      aItems.forEach(function (oItem, i) {
        var oMig = aCreated.find(function (m) { return m.FormName === oItem.FormName; });
        var sPath = "/commit/items/" + i;
        if (!oMig) {
          var oMsg = aMessages.find(function (m) { return m.text.indexOf(oItem.FormName) === 0; });
          oView.setProperty(sPath + "/state", "Warning");
          oView.setProperty(sPath + "/icon", "sap-icon://warning");
          oView.setProperty(sPath + "/text", oMsg ? oMsg.text : that.i18n("notCommitted"));
          return;
        }
        oView.setProperty(sPath + "/mig", oMig);
        oView.setProperty(sPath + "/state", bDrafts ? "Warning" : "Information");
        oView.setProperty(sPath + "/icon", bDrafts ? "sap-icon://save" : "sap-icon://pending");
        oView.setProperty(sPath + "/text", that.i18n("committedSerial", [oMig.SerialNo]) + " · " +
          that.i18n(bDrafts ? "savedAsDraft" : "sending"));
      });

      // One form after the other, each with its own live result. A failing form
      // stays as a draft and never holds back the others.
      if (!bDrafts) {
        for (var i = 0; i < aItems.length; i++) {
          var oMig = oView.getProperty("/commit/items/" + i + "/mig");
          if (oMig) {
            await this._sendOne(oMig, "/commit/items/" + i);
          }
        }
      }
      oView.setProperty("/commit/busy", false);
      oView.setProperty("/commit/done", true);
      this.reload();
    },

    /** Sends one migration to GitHub and writes the result into the given row of the view model. */
    _sendOne: async function (oMig, sPath) {
      var oView = this.getView().getModel("view");
      try {
        var oAfter = await this.service().action(service.migPath(oMig.MigUuid), "pushToGitHub", {});
        var aMsg = this.takeMessages();
        if (oAfter && oAfter.PushStatus === "PUSHED") {
          oView.setProperty(sPath + "/state", "Success");
          oView.setProperty(sPath + "/icon", "sap-icon://upload-to-cloud");
          oView.setProperty(sPath + "/text", this.i18n("committedSerial", [oMig.SerialNo]) + " · " +
            this.i18n("sentFiles", [oAfter.FilesCount, oAfter.BranchName]));
          return true;
        }
        var oWarn = aMsg.find(function (m) { return m.type === "Warning" || m.type === "Error"; });
        oView.setProperty(sPath + "/state", "Error");
        oView.setProperty(sPath + "/icon", "sap-icon://error");
        oView.setProperty(sPath + "/text", this.i18n("keptAsDraft") + (oWarn ? " " + oWarn.text : ""));
      } catch (oError) {
        oView.setProperty(sPath + "/state", "Error");
        oView.setProperty(sPath + "/icon", "sap-icon://error");
        oView.setProperty(sPath + "/text", this.i18n("keptAsDraft") + " " + this.errorOf(oError));
      }
      return false;
    },

    onCloseCommit: function () {
      var oView = this.getView().getModel("view");
      var bDone = oView.getProperty("/commit/done");
      var bAnyDraft = (oView.getProperty("/commit/items") || []).some(function (o) {
        return o.mig && o.state !== "Success";
      });
      this._oCommitDialog.close();
      if (bDone) {
        var sTab = bAnyDraft ? "drafts" : "migrations";
        oView.setProperty("/tab", sTab);
        this.router().navTo("dashboard", { tab: sTab }, true);
      }
    },

    // ================================ 2. Drafts ================================

    /** Send to GitHub for one draft row. */
    onSendDraft: async function (oEvent) {
      var oCtx = oEvent.getSource().getBindingContext("view");
      var oMig = oCtx.getObject();
      var oView = this.getView().getModel("view");
      oView.setProperty("/draftBusy", true);
      var bSent = await this._sendOne(oMig, oCtx.getPath());
      oView.setProperty("/draftBusy", false);
      var sText = oView.getProperty(oCtx.getPath() + "/text");
      if (bSent) {
        MessageToast.show(sText, { duration: 5000, width: "30rem" });
      } else {
        MessageBox.error(sText, { contentWidth: "40rem", styleClass: "boltMsgWrap" });
      }
      this.reload();
    },

    /** Send every draft, one after the other, then one summary. */
    onSendAllDrafts: async function () {
      var oView = this.getView().getModel("view");
      var aDrafts = (oView.getProperty("/drafts") || []).slice();
      var iSent = 0;
      oView.setProperty("/draftBusy", true);
      for (var i = 0; i < aDrafts.length; i++) {
        if (await this._sendOne(aDrafts[i], "/drafts/" + i)) { iSent += 1; }
      }
      oView.setProperty("/draftBusy", false);
      var iLeft = aDrafts.length - iSent;
      if (iLeft) {
        MessageBox.warning(this.i18n("draftsSentSome", [iSent, iLeft]), { contentWidth: "36rem", styleClass: "boltMsgWrap" });
      } else {
        MessageToast.show(this.i18n("draftsSentAll", [iSent]), { duration: 5000 });
      }
      this.reload();
    },

    /** Discard = a local stop: the draft leaves the list, the form can be selected again. */
    onDiscardDraft: function (oEvent) {
      var that = this;
      var oMig = oEvent.getSource().getBindingContext("view").getObject();
      MessageBox.confirm(this.i18n("discardConfirm", [oMig.FormName, oMig.SerialNo]), {
        onClose: async function (sAction) {
          if (sAction !== MessageBox.Action.OK) { return; }
          await that.withBusy(async function () {
            await that.service().action(service.migPath(oMig.MigUuid), "requestStop", { Reason: that.i18n("discardReason") });
            that.takeMessages();
            MessageToast.show(that.i18n("discarded", [oMig.FormName]));
            await that.reload();
          }, "view", "/draftBusy");
        }
      });
    },

    // ================================ 3. Migrations ================================

    loadMigrations: async function () {
      var oView = this.getView().getModel("view");
      oView.setProperty("/migBusy", true);
      try {
        var aMig = await this.service().list("/Migration", { sorters: [new Sorter("SerialNo", true)] });
        this._setMigrations(aMig);
      } catch (oError) {
        this.showError(oError);
      } finally {
        oView.setProperty("/migBusy", false);
      }
    },

    _setMigrations: function (aMig) {
      var oView = this.getView().getModel("view");
      aMig.forEach(function (o) {
        o.statusText = formatter.rowStatusText(o);
        o.statusState = formatter.rowStatusState(o);
        o.needsClient = formatter.needsClient(o);
        // Waiting on comes from the status file - meaningless until the migration is on GitHub.
        o.waitingText = o.PushStatus === "PUSHED" && !formatter.isX(o.Superseded) ? formatter.waitingText(o.WaitingOn) : "";
        o.isStopped = formatter.isX(o.Stopped);
        // Time since the commit (open) or from commit to completion (took).
        o.ageText = formatter.ageText(o) ? this.i18n(formatter.isCompleted(o) ? "ageTook" : "ageOpen", [formatter.ageText(o)]) : "";
        o.ageState = formatter.ageState(o);
        o.category = formatter.category(o);
      }, this);
      var aDrafts = aMig.filter(function (o) { return o.category === "draft"; })
        .sort(function (a, b) { return a.SerialNo - b.SerialNo; });
      // The Migrations tab: everything except open drafts (a discarded draft is "stopped").
      var aOnGitHub = aMig.filter(function (o) { return o.category !== "draft"; });
      var aLive = aOnGitHub.filter(function (o) { return o.category !== "replaced"; });
      oView.setProperty("/drafts", aDrafts);
      oView.setProperty("/migrations", aOnGitHub);
      oView.setProperty("/counts/drafts", aDrafts.length);
      oView.setProperty("/counts/migAll", aLive.length);
      oView.setProperty("/counts/needs", aLive.filter(function (o) { return o.needsClient; }).length);
      ["active", "stopped", "completed"].forEach(function (sCat) {
        oView.setProperty("/counts/" + sCat, aLive.filter(function (o) { return o.category === sCat; }).length);
      });
      this.applyMigrationFilter();
    },

    applyMigrationFilter: function () {
      var oView = this.getView().getModel("view");
      var sSearch = (oView.getProperty("/migSearch") || "").trim().toLowerCase();
      var sFilter = oView.getProperty("/migFilter");
      var bReplaced = oView.getProperty("/showReplaced");
      var aShown = (oView.getProperty("/migrations") || []).filter(function (o) {
        if (o.category === "replaced" && !bReplaced) { return false; }
        if (sFilter === "needs" && !o.needsClient) { return false; }
        if (["active", "stopped", "completed"].indexOf(sFilter) >= 0 && o.category !== sFilter) { return false; }
        if (!sSearch) { return true; }
        return [o.FormName, o.FormDescr, o.BranchName, String(o.SerialNo), o.statusText].some(function (s) {
          return String(s || "").toLowerCase().indexOf(sSearch) >= 0;
        });
      });
      oView.setProperty("/migrationsShown", aShown);
    },

    onMigrationSearch: function () { this.applyMigrationFilter(); },
    onMigrationFilter: function () { this.applyMigrationFilter(); },

    onMigrationPress: function (oEvent) {
      var oMig = oEvent.getSource().getBindingContext("view").getObject();
      this.router().navTo("detail", { migUuid: oMig.MigUuid });
    },

    /** Reads every open migration's status file from GitHub (refreshAll). */
    onRefreshStatuses: async function () {
      var that = this;
      await this.withBusy(async function () {
        var aRefreshed = await that.service().listAction("/Migration", "refreshAll", {});
        that._markGitHubRead();
        that.showMessages(that.i18n("statusesRead", [aRefreshed.length]));
        await that.loadMigrations();
      }, "view", "/migBusy");
    },

    onExportMigrations: function () {
      var aCols = [
        { label: this.i18n("colSerial"), property: "SerialNo", type: "Number" },
        { label: this.i18n("colForm"), property: "FormName" },
        { label: this.i18n("colDescription"), property: "FormDescr" },
        { label: this.i18n("colRun"), property: "RunNo", type: "Number" },
        { label: this.i18n("colBranch"), property: "BranchName" },
        { label: this.i18n("colStatus"), property: "statusText" },
        { label: this.i18n("colWaitingOn"), property: "WaitingOn" },
        { label: this.i18n("colPickedUp"), property: "ClaimedBy" },
        { label: this.i18n("colComplexity"), property: "Complexity" },
        { label: this.i18n("colFiles"), property: "FilesCount", type: "Number" },
        { label: this.i18n("colCommitted"), property: "createdText" },
        { label: this.i18n("colPickedUpAt"), property: "pickedText" },
        { label: this.i18n("colCompletedAt"), property: "completedText" },
        { label: this.i18n("colCommittedBy"), property: "CreatedBy" }
      ];
      var aRows = this.getView().getModel("view").getProperty("/migrationsShown").map(function (o) {
        return Object.assign({}, o, {
          createdText: formatter.dateTime(o.CreatedAt), pickedText: formatter.dateTime(o.PickedUpAt),
          completedText: formatter.dateTime(o.CompletedAt)
        });
      });
      this._export(aCols, aRows, "Migrations_" + (this.appModel().getProperty("/sys/SystemId") || ""));
    },

    _export: function (aCols, aRows, sName) {
      sap.ui.require(["sap/ui/export/Spreadsheet"], function (Spreadsheet) {
        var oSheet = new Spreadsheet({
          workbook: { columns: aCols.map(function (c) { return Object.assign({ type: "String" }, c); }) },
          dataSource: aRows,
          fileName: sName + ".xlsx"
        });
        oSheet.build().finally(function () { oSheet.destroy(); });
      }, function () {
        MessageBox.information("Export to spreadsheet needs the library sap.ui.export.");
      });
    }
  });
});
