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

  var DEFAULT_MODEL = { openai: "gpt-4o-mini", anthropic: "claude-sonnet-5-5", mock: "built-in" };
  var LIB_FOLDERS = { logo: "logos", smartstyle: "styles", naming_standard: "naming_standards", policy: "policies" };

  return BaseController.extend("vernasoft.boltfiori.controller.Dashboard", {

    onInit: function () {
      this.getView().setModel(new JSONModel({
        tab: "forms",
        kpi: { forms: 0, total: 0, waiting: 0, active: 0, stopped: 0, completed: 0 },
        forms: [], formsShown: [], formsBusy: false, formsError: "", search: "", formFilter: "all", selectedCount: 0,
        migrations: [], migrationsShown: [], migBusy: false, migSearch: "", migFilter: "all", showReplaced: false,
        lastRefreshText: "",
        commit: { items: [], committed: false, busy: false, done: false },
        cfg: {}, cfgBusy: false, token: "",
        ai: { Provider: "mock", Model: "", BaseUrl: "", MaxTokens: 4096, ApiKey: "", keySaved: false, blockedForKey: false,
              defaultModel: "built-in", currentText: "", testText: "", testOk: false },
        repo: { Repo: "", BranchPrefix: "", checkText: "", checkOk: false },
        lib: { Category: "logo", Provenance: "", files: [] },
        library: []
      }), "view");
      this.router().getRoute("dashboard").attachPatternMatched(this._onMatched, this);
      this.enableDropZones();
    },

    _onMatched: function (oEvent) {
      var sTab = (oEvent.getParameter("arguments") || {}).tab;
      if (sTab) { this.getView().getModel("view").setProperty("/tab", sTab); }
      if (!this._bLoaded) {
        this._bLoaded = true;
        this.reload();
      } else {
        this.loadMigrations();
        this.loadForms();
      }
    },

    reload: async function () {
      var that = this;
      await this.withBusy(async function () {
        await that.loadContext();
        that.fillConfig();
      });
      await Promise.all([this.loadForms(), this.loadMigrations(), this.loadLibrary()]);
    },

    // ================================ header ================================

    onRefreshAll: function () { this.reload(); },

    onOpenConfiguration: function () { this.getView().getModel("view").setProperty("/tab", "config"); },

    onTabSelect: function (oEvent) {
      this.router().navTo("dashboard", { tab: oEvent.getParameter("key") }, true);
    },

    onKpiPress: function (oEvent) {
      var sTarget = oEvent.getSource().data("target");
      var oView = this.getView().getModel("view");
      if (sTarget === "forms") {
        oView.setProperty("/tab", "forms");
        return;
      }
      oView.setProperty("/tab", "migration");
      oView.setProperty("/migFilter", sTarget);
      this.applyMigrationFilter();
    },

    // ================================ Smart Forms tab ================================

    loadForms: async function () {
      var oView = this.getView().getModel("view");
      oView.setProperty("/formsBusy", true);
      oView.setProperty("/formsError", "");
      try {
        var aForms = await this.service().list("/SmartForm");
        aForms.forEach(function (o) { o.selected = false; o.Selectable = formatter.isX(o.Selectable); });
        oView.setProperty("/forms", aForms);
        oView.setProperty("/kpi/forms", aForms.length);
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
        return [o.FormName, o.Description, o.DevPackage, o.DriverProgs].some(function (s) {
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

    /** A form in migration or completed cannot be selected again (one active branch per form). */
    onFormSelect: function (oEvent) {
      var that = this;
      var aRefused = [];
      var aItems = oEvent.getParameter("listItems") || [oEvent.getParameter("listItem")];
      aItems.forEach(function (oItem) {
        var oCtx = oItem && oItem.getBindingContext("view");
        if (!oCtx) { return; }
        var oForm = oCtx.getObject();
        if (oItem.getSelected() && !oForm.Selectable) {
          oCtx.getModel().setProperty(oCtx.getPath() + "/selected", false);
          aRefused.push(oForm.FormName + (oForm.MigState === "COMPLETED" ? that.i18n("refusedCompleted") : that.i18n("refusedActive")));
        }
      });
      if (aRefused.length) {
        MessageToast.show(aRefused.join("\n"), { duration: 5000, width: "32rem" });
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

    // ---- Next > confirmation > Commit > automatic transfer ------------------------

    onNext: async function () {
      var oView = this.getView().getModel("view");
      var aSelected = (oView.getProperty("/forms") || []).filter(function (o) { return o.selected && o.Selectable; });
      if (!aSelected.length) { return; }
      oView.setProperty("/commit", {
        committed: false, busy: false, done: false,
        items: aSelected.map(function (o) {
          return {
            FormName: o.FormName, Description: o.Description,
            reprocess: o.MigState === "STOPPED", nextRun: (o.LastRunNo || 0) + 1,
            state: "None", icon: "sap-icon://document", text: o.MigState === "STOPPED" ? "Re-process run " + ((o.LastRunNo || 0) + 1) : ""
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

      // Mark the forms that were skipped (another user committed them meanwhile).
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
        oView.setProperty(sPath + "/state", "Information");
        oView.setProperty(sPath + "/icon", "sap-icon://pending");
        oView.setProperty(sPath + "/text", that.i18n("committedSerial", [oMig.SerialNo]) + " · " + that.i18n("sending"));
      });

      // One form after the other, each with its own result - a slow or failing
      // form never holds back the others, and the user sees progress live.
      for (var i = 0; i < aItems.length; i++) {
        var oMig = oView.getProperty("/commit/items/" + i + "/mig");
        if (!oMig) { continue; }
        var sPath = "/commit/items/" + i;
        try {
          var oAfter = await this.service().action(service.migPath(oMig.MigUuid), "pushToGitHub", {});
          var aMsg = this.takeMessages();
          if (oAfter && oAfter.PushStatus === "PUSHED") {
            oView.setProperty(sPath + "/state", "Success");
            oView.setProperty(sPath + "/icon", "sap-icon://upload-to-cloud");
            oView.setProperty(sPath + "/text", that.i18n("committedSerial", [oMig.SerialNo]) + " · " +
              that.i18n("sentFiles", [oAfter.FilesCount, oAfter.BranchName]));
          } else {
            var oWarn = aMsg.find(function (m) { return m.type === "Warning" || m.type === "Error"; });
            oView.setProperty(sPath + "/state", "Error");
            oView.setProperty(sPath + "/icon", "sap-icon://error");
            oView.setProperty(sPath + "/text", that.i18n("sendFailed") + (oWarn ? " " + oWarn.text : ""));
          }
        } catch (oError) {
          oView.setProperty(sPath + "/state", "Error");
          oView.setProperty(sPath + "/icon", "sap-icon://error");
          oView.setProperty(sPath + "/text", that.i18n("sendFailed") + " " + this.errorOf(oError));
        }
      }
      oView.setProperty("/commit/busy", false);
      oView.setProperty("/commit/done", true);
      this.loadForms();
      this.loadMigrations();
    },

    onCloseCommit: function () {
      var bDone = this.getView().getModel("view").getProperty("/commit/done");
      this._oCommitDialog.close();
      if (bDone) {
        this.getView().getModel("view").setProperty("/tab", "migration");
        this.router().navTo("dashboard", { tab: "migration" }, true);
      }
    },

    // ================================ Migration tab ================================

    loadMigrations: async function () {
      var oView = this.getView().getModel("view");
      oView.setProperty("/migBusy", true);
      try {
        var aMig = await this.service().list("/Migration", {
          sorters: [new Sorter("SerialNo", true)]
        });
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
        o.ageText = formatter.ageText(o);
        o.ageState = formatter.ageState(o);
        o.category = formatter.category(o);
      });
      var aLive = aMig.filter(function (o) { return o.category !== "replaced"; });
      oView.setProperty("/migrations", aMig);
      oView.setProperty("/kpi/total", aLive.length);
      oView.setProperty("/kpi/waiting", aLive.filter(function (o) { return o.needsClient; }).length);
      oView.setProperty("/kpi/active", aLive.filter(function (o) { return o.category === "active"; }).length);
      oView.setProperty("/kpi/stopped", aLive.filter(function (o) { return o.category === "stopped"; }).length);
      oView.setProperty("/kpi/completed", aLive.filter(function (o) { return o.category === "completed"; }).length);
      oView.setProperty("/lastRefreshText", this.i18n("lastRefresh", [new Date().toLocaleTimeString([], { timeStyle: "short" })]));
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
        if (["active", "stopped", "completed", "problems"].indexOf(sFilter) >= 0 && o.category !== sFilter) { return false; }
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
    },

    // ================================ Configuration tab ================================

    /** Copies the setup row into the edit fields of the Configuration tab. */
    fillConfig: function () {
      var oSetup = this.appModel().getProperty("/setup") || {};
      var oView = this.getView().getModel("view");
      oView.setProperty("/cfg", {
        CustomerName: oSetup.CustomerName || "", AdminUsers: oSetup.AdminUsers || "",
        GhApiUrl: oSetup.GhApiUrl || "", SslId: oSetup.SslId || "", GhDest: oSetup.GhDest || "", AiDest: oSetup.AiDest || "",
        StatusFolder: oSetup.StatusFolder || "", LibFolder: oSetup.LibFolder || "", FormPrefixes: oSetup.FormPrefixes || "",
        CountVolume: formatter.isX(oSetup.CountVolume)
      });
      var sProvider = oSetup.AiProvider || "mock";
      oView.setProperty("/ai", {
        Provider: sProvider, Model: oSetup.AiModel || "", BaseUrl: oSetup.AiBaseUrl || "",
        MaxTokens: oSetup.AiMaxTokens || 4096, ApiKey: "", testText: "", testOk: false
      });
      oView.setProperty("/repo", {
        Repo: oSetup.GhRepo || "", BranchPrefix: oSetup.GhBranchPfx || "",
        checkText: oSetup.GhCheckMsg || "", checkOk: oSetup.GhCheckRes === "OK"
      });
      this._aiDerived();
    },

    aiLabel: function (s) {
      return { openai: "OpenAI", anthropic: "Anthropic" }[s] || "Built-in (offline)";
    },

    libFolder: function (s) { return LIB_FOLDERS[s] || s || ""; },

    /** keyIsSaved / needsKey / blockedForKey of AiSettings.jsx. */
    _aiDerived: function () {
      var oView = this.getView().getModel("view");
      var oSetup = this.appModel().getProperty("/setup") || {};
      var sProvider = oView.getProperty("/ai/Provider");
      var bNeedsKey = sProvider !== "mock";
      var bKeySaved = formatter.isX(oSetup.AiKeySet) && oSetup.AiProvider === sProvider;
      oView.setProperty("/ai/keySaved", bKeySaved);
      oView.setProperty("/ai/blockedForKey", bNeedsKey && !bKeySaved && !oView.getProperty("/ai/ApiKey"));
      oView.setProperty("/ai/defaultModel", DEFAULT_MODEL[sProvider] || "model name");
      oView.setProperty("/ai/currentText", this.i18n("currentlyUsing") + " " + this.aiLabel(oSetup.AiProvider) + " · " +
        (oSetup.AiModel || DEFAULT_MODEL[oSetup.AiProvider || "mock"]));
    },

    onAiProviderChange: function () {
      this.getView().getModel("view").setProperty("/ai/Model", "");
      this.getView().getModel("view").setProperty("/ai/testText", "");
      this._aiDerived();
    },

    _setupPath: function () { return "/Setup('DEFAULT')"; },

    /**
     * After any setup change: reload the row and the readiness. What the user is
     * typing in the AI and repository cards is kept, unless that card was just saved.
     */
    _afterSetup: async function (sSaved) {
      await this.loadContext();
      var oView = this.getView().getModel("view");
      var oKeep = { ai: oView.getProperty("/ai"), repo: oView.getProperty("/repo") };
      this.fillConfig();
      if (sSaved !== "repo") {
        oView.setProperty("/repo/Repo", oKeep.repo.Repo);
        oView.setProperty("/repo/BranchPrefix", oKeep.repo.BranchPrefix);
        oView.setProperty("/repo/checkText", oKeep.repo.checkText);
        oView.setProperty("/repo/checkOk", oKeep.repo.checkOk);
      }
      if (sSaved === "ai") {
        this._aiDerived();
        return;
      }
      oView.setProperty("/ai/Provider", oKeep.ai.Provider);
      oView.setProperty("/ai/Model", oKeep.ai.Model);
      oView.setProperty("/ai/BaseUrl", oKeep.ai.BaseUrl);
      oView.setProperty("/ai/MaxTokens", oKeep.ai.MaxTokens);
      oView.setProperty("/ai/testText", oKeep.ai.testText);
      oView.setProperty("/ai/testOk", oKeep.ai.testOk);
      this._aiDerived();
    },

    _patch: async function (mChanges, sDone) {
      var that = this;
      var bSaved = await this.withBusy(async function () {
        await that.service().update(that._setupPath(), mChanges);
        that.showMessages(sDone);
        await that._afterSetup();
        return true;
      }, "view", "/cfgBusy");
      if (!bSaved) {
        // Refused (e.g. own user missing from the administrators): show the saved values again.
        var oSetup = this.appModel().getProperty("/setup") || {};
        var oView = this.getView().getModel("view");
        Object.keys(mChanges).forEach(function (sName) {
          var vSaved = oSetup[sName];
          oView.setProperty("/cfg/" + sName, typeof vSaved === "boolean" ? vSaved : (vSaved || ""));
        });
      }
      return bSaved;
    },

    /** Client name saves when the field is left (Configure.jsx onBlur). */
    onCustomerBlur: function () {
      var sName = (this.getView().getModel("view").getProperty("/cfg/CustomerName") || "").trim();
      if (sName === (this.appModel().getProperty("/setup/CustomerName") || "")) { return; }
      this._patch({ CustomerName: sName }, this.i18n("savedClientName"));
    },

    onAdminsBlur: function () {
      var sAdmins = (this.getView().getModel("view").getProperty("/cfg/AdminUsers") || "").toUpperCase().replace(/\s+/g, "");
      if (sAdmins === (this.appModel().getProperty("/setup/AdminUsers") || "")) { return; }
      this._patch({ AdminUsers: sAdmins }, this.i18n("savedAdmins"));
    },

    onSaveAdvanced: function () {
      var c = this.getView().getModel("view").getProperty("/cfg");
      this._patch({
        GhApiUrl: (c.GhApiUrl || "").trim(), SslId: (c.SslId || "").trim().toUpperCase(),
        GhDest: (c.GhDest || "").trim().toUpperCase(), AiDest: (c.AiDest || "").trim().toUpperCase(),
        StatusFolder: (c.StatusFolder || "").trim(), LibFolder: (c.LibFolder || "").trim(),
        FormPrefixes: (c.FormPrefixes || "").trim().toUpperCase(), CountVolume: !!c.CountVolume
      }, this.i18n("savedAdvanced")).then(this.loadForms.bind(this));
    },

    // ---- GitHub connection (GitHubConnection.jsx) ----

    onConnectGitHub: async function () {
      var that = this;
      var oView = this.getView().getModel("view");
      var sToken = (oView.getProperty("/token") || "").trim();
      if (!sToken) { return; }
      await this.withBusy(async function () {
        await that.service().action(that._setupPath(), "connectGitHub", { Token: sToken });
        oView.setProperty("/token", "");
        that.showMessages();
        await that._afterSetup();
      }, "view", "/cfgBusy");
    },

    onDisconnectGitHub: function () {
      var that = this;
      MessageBox.confirm(this.i18n("disconnectConfirm"), {
        onClose: async function (sAction) {
          if (sAction !== MessageBox.Action.OK) { return; }
          await that.withBusy(async function () {
            await that.service().action(that._setupPath(), "disconnectGitHub", {});
            that.showMessages();
            await that._afterSetup();
          }, "view", "/cfgBusy");
        }
      });
    },

    onTokenHelp: function () {
      MessageBox.information(this.i18n("tokenHelp"), { title: this.i18n("howToken"), contentWidth: "36rem" });
    },

    // ---- AI provider (AiSettings.jsx) ----

    _aiParams: function () {
      var a = this.getView().getModel("view").getProperty("/ai");
      return { Provider: a.Provider, Model: (a.Model || "").trim(), BaseUrl: (a.BaseUrl || "").trim(),
               MaxTokens: +a.MaxTokens || 4096, ApiKey: (a.ApiKey || "").trim() };
    },

    onTestAi: async function () {
      var that = this;
      var oView = this.getView().getModel("view");
      await this.withBusy(async function () {
        await that.service().action(that._setupPath(), "testAi", that._aiParams());
        var aMsg = that.takeMessages();
        var oMsg = aMsg[0] || { type: "Success", text: "" };
        oView.setProperty("/ai/testText", oMsg.text);
        oView.setProperty("/ai/testOk", oMsg.type === "Success");
        await that._afterSetup();
      }, "view", "/cfgBusy");
    },

    onSaveAi: async function () {
      var that = this;
      var oView = this.getView().getModel("view");
      await this.withBusy(async function () {
        await that.service().action(that._setupPath(), "saveAi", that._aiParams());
        oView.setProperty("/ai/ApiKey", "");
        that.showMessages();
        await that._afterSetup("ai");
      }, "view", "/cfgBusy");
    },

    // ---- 2. Repository (TargetRepo.jsx) ----

    onPrefixLive: function () { /* the example under the field is bound - nothing to do */ },

    _repoParams: function () {
      var r = this.getView().getModel("view").getProperty("/repo");
      return { Repo: (r.Repo || "").trim(), BranchPrefix: (r.BranchPrefix || "").trim() };
    },

    onCheckRepo: async function () {
      var that = this;
      var oView = this.getView().getModel("view");
      await this.withBusy(async function () {
        await that.service().action(that._setupPath(), "checkRepo", that._repoParams());
        var oMsg = that.takeMessages()[0] || { type: "Warning", text: "" };
        oView.setProperty("/repo/checkText", oMsg.text);
        oView.setProperty("/repo/checkOk", oMsg.type === "Success");
      }, "view", "/cfgBusy");
    },

    onCreateRepo: function () {
      var that = this;
      var sName = this._repoParams().Repo;
      MessageBox.confirm(this.i18n("createRepoConfirm", [sName, this.appModel().getProperty("/setup/GhLogin")]), {
        onClose: async function (sAction) {
          if (sAction !== MessageBox.Action.OK) { return; }
          await that.withBusy(async function () {
            var oSetup = await that.service().action(that._setupPath(), "createRepo", that._repoParams());
            that.showMessages();
            await that._afterSetup("repo");
            var oView = that.getView().getModel("view");
            oView.setProperty("/repo/Repo", (oSetup && oSetup.GhRepo) || sName);
          }, "view", "/cfgBusy");
        }
      });
    },

    onSaveRepo: async function () {
      var that = this;
      await this.withBusy(async function () {
        await that.service().action(that._setupPath(), "saveRepo", that._repoParams());
        that.showMessages();
        await that._afterSetup("repo");
      }, "view", "/cfgBusy");
    },

    // ---- Global reference library (GlobalLibrary.jsx) ----

    loadLibrary: async function () {
      try {
        var aLib = await this.service().list("/Library", {
          sorters: [new Sorter("LibCategory"), new Sorter("FileName")]
        });
        aLib.forEach(function (o) { o.Pushed = formatter.isX(o.Pushed); });
        this.getView().getModel("view").setProperty("/library", aLib);
      } catch (e) {
        this.getView().getModel("view").setProperty("/library", []);
      }
    },

    onLibFiles: function (oEvent) {
      this.stageFiles(oEvent.getParameter("files"), "view", "/lib/files");
      oEvent.getSource().clear();
    },

    onLibUnstage: function (oEvent) { this.unstageFile(oEvent, "view", "/lib/files"); },

    onLibUpload: async function () {
      var that = this;
      var oView = this.getView().getModel("view");
      var oLib = oView.getProperty("/lib");
      await this.withBusy(async function () {
        await that.service().listAction("/Library", "upload", {
          Category: oLib.Category, Provenance: (oLib.Provenance || "").trim(), FilesJson: await that.filesJson(oLib.files)
        });
        oView.setProperty("/lib/files", []);
        oView.setProperty("/lib/Provenance", "");
        that.showMessages();
        await that.loadLibrary();
      }, "view", "/cfgBusy");
    },

    onLibRemove: function (oEvent) {
      var that = this;
      var oFile = oEvent.getSource().getBindingContext("view").getObject();
      MessageBox.confirm(this.i18n("libRemoveConfirm", [oFile.FileName]), {
        onClose: async function (sAction) {
          if (sAction !== MessageBox.Action.OK) { return; }
          await that.withBusy(async function () {
            await that.service().remove("/Library(LibUuid=" + oFile.LibUuid + ")");
            MessageToast.show(that.i18n("libRemoved", [oFile.FileName]));
            await that.loadLibrary();
          }, "view", "/cfgBusy");
        }
      });
    }
  });
});
