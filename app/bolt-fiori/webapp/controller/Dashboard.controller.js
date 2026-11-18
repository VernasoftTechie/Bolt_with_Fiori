sap.ui.define([
  "vernasoft/boltfiori/controller/BaseController",
  "sap/ui/model/json/JSONModel",
  "sap/ui/model/Filter",
  "sap/ui/model/FilterOperator",
  "sap/ui/model/Sorter",
  "sap/ui/core/Fragment",
  "sap/m/MessageToast",
  "sap/m/MessageBox",
  "vernasoft/boltfiori/model/formatter"
], function (BaseController, JSONModel, Filter, FilterOperator, Sorter, Fragment, MessageToast, MessageBox, formatter) {
  "use strict";

  var CONFIG_FIELDS = ["CustomerName", "AdminUsers", "AiProvider", "AiModel", "AiDestination", "AiBasePath", "AiMaxTokens",
    "GhDestination", "GhOwner", "GhRepo", "GhBaseBranch", "GhBranchPrefix", "FormPrefix1", "FormPrefix2", "CountVolume"];
  var AUTO_REFRESH_MS = 120000;

  return BaseController.extend("vernasoft.boltfiori.controller.Dashboard", {

    onInit: function () {
      this.getView().setModel(new JSONModel({
        tab: "overview",
        systemId: "",
        forms: [],
        formsShown: [],
        formsBusy: false,
        formsError: "",
        search: "",
        formFilter: "all",
        selectedCount: 0,
        migrations: [],
        migrationsShown: [],
        migBusy: false,
        migSearch: "",
        migFilter: "all",
        showWithdrawn: false,
        kpi: { forms: 0, total: 0, waiting: 0, active: 0, completed: 0, problems: 0 },
        config: {},
        aiKey: "",
        configBusy: false,
        configMessage: "",
        commit: { phase: "confirm", items: [] },
        systemEdit: {}
      }), "view");
      this._bLoaded = false;
      this.router().getRoute("dashboard").attachPatternMatched(this._onRouteMatched, this);
    },

    onExit: function () {
      this._stopAutoRefresh();
    },

    _onRouteMatched: function (oEvent) {
      var sTab = (oEvent.getParameter("arguments") || {}).tab;
      if (sTab) {
        this.getView().getModel("view").setProperty("/tab", sTab);
      }
      if (!this._bLoaded) {
        this._bLoaded = true;
        this._initialLoad();
      } else {
        // Back from a migration: show the latest state without another GitHub round.
        this._loadMigrations();
      }
    },

    _initialLoad: async function () {
      await this.withBusy(async function () {
        var oSetup = await this.loadSetup();
        this._resetConfig(oSetup);
        var aSystems = this.appModel().getProperty("/systems");
        var oDefault = aSystems.find(function (s) { return s.IsDefault === "X"; }) || aSystems[0];
        this.getView().getModel("view").setProperty("/systemId", oDefault ? oDefault.SystemId : "");
        this.appModel().setProperty("/selectedSystem", oDefault ? oDefault.SystemId : "");
        this.updateReadiness();
      }.bind(this));
      this._loadForms();
      // Like the web app: the latest status from the branches every time the page opens.
      this._refreshStatuses(true);
    },

    // ------------------------------------------------------------------ header
    onRefreshAll: async function () {
      await this.withBusy(async function () {
        var oSetup = await this.loadSetup();
        this._resetConfig(oSetup);
      }.bind(this));
      this._loadForms();
      this._refreshStatuses(false);
    },

    onToggleAutoRefresh: function (oEvent) {
      if (oEvent.getParameter("state")) {
        this._oTimer = setInterval(function () { this._refreshStatuses(true); }.bind(this), AUTO_REFRESH_MS);
        MessageToast.show(this.i18n("autoRefreshOn"));
      } else {
        this._stopAutoRefresh();
      }
    },

    _stopAutoRefresh: function () {
      if (this._oTimer) {
        clearInterval(this._oTimer);
        this._oTimer = null;
      }
    },

    onOpenConfiguration: function () {
      this.getView().getModel("view").setProperty("/tab", "config");
    },

    onTabSelect: function (oEvent) {
      var sKey = oEvent.getParameter("key");
      if (sKey === "migration") {
        this._loadMigrations();
      }
    },

    onKpiPress: function (oEvent) {
      var sTarget = oEvent.getSource().data("target");
      var oView = this.getView().getModel("view");
      if (sTarget === "overview") {
        oView.setProperty("/tab", "overview");
        return;
      }
      oView.setProperty("/tab", "migration");
      oView.setProperty("/migFilter", sTarget);
      this._applyMigrationFilter();
    },

    formatLastRefresh: function (oDate) {
      return oDate ? this.i18n("lastRefreshed", [oDate.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })]) : "";
    },

    // -------------------------------------------------------- Smart Forms overview
    onSystemChange: function () {
      var sId = this.getView().getModel("view").getProperty("/systemId");
      this.appModel().setProperty("/selectedSystem", sId);
      this.updateReadiness(sId);
      this._loadForms();
    },

    _loadForms: async function () {
      var oView = this.getView().getModel("view");
      var sSystem = oView.getProperty("/systemId");
      if (!sSystem) {
        oView.setProperty("/forms", []);
        oView.setProperty("/formsError", this.i18n("noSystemConfigured"));
        this._applyFormFilter();
        return;
      }
      oView.setProperty("/formsBusy", true);
      oView.setProperty("/formsError", "");
      try {
        var aRows = await this.service().list("/SmartForm", {
          filters: [new Filter("SystemId", FilterOperator.EQ, sSystem)],
          sorters: [new Sorter("FormName")]
        });
        var oError = aRows.find(function (r) { return r.FormName === "*ERROR*"; });
        if (oError) {
          oView.setProperty("/formsError", oError.Message);
          aRows = [];
        }
        aRows.forEach(function (r) { r.selected = false; });
        oView.setProperty("/forms", aRows);
      } catch (e) {
        oView.setProperty("/forms", []);
        oView.setProperty("/formsError", this.service().errorText(e));
      } finally {
        oView.setProperty("/formsBusy", false);
      }
      this._applyFormFilter();
    },

    onFormSearch: function () { this._applyFormFilter(); },
    onFormFilter: function () { this._applyFormFilter(); },

    _applyFormFilter: function () {
      var oView = this.getView().getModel("view");
      var sSearch = (oView.getProperty("/search") || "").trim().toUpperCase();
      var sFilter = oView.getProperty("/formFilter");
      var aForms = oView.getProperty("/forms") || [];
      var aShown = aForms.filter(function (f) {
        if (sFilter === "available" && f.InMigration) { return false; }
        if (sFilter === "inmig" && !f.InMigration) { return false; }
        if (!sSearch) { return true; }
        return [f.FormName, f.Description, f.DriverProgram, f.DevPackage].some(function (s) {
          return String(s || "").toUpperCase().indexOf(sSearch) >= 0;
        });
      });
      oView.setProperty("/formsShown", aShown);
      oView.setProperty("/kpi/forms", aForms.length);
      this._countSelected();
    },

    onFormSelect: function (oEvent) {
      var oView = this.getView().getModel("view");
      var aBlocked = [];
      (oEvent.getParameter("listItems") || []).forEach(function (oItem) {
        var oCtx = oItem.getBindingContext("view");
        var oForm = oCtx && oCtx.getObject();
        if (oForm && oForm.InMigration && oItem.getSelected()) {
          oItem.setSelected(false);
          oView.setProperty(oCtx.getPath() + "/selected", false);
          aBlocked.push(oForm.FormName);
        }
      });
      if (aBlocked.length) {
        MessageToast.show(this.i18n("alreadyInMigration", [aBlocked.slice(0, 5).join(", ") + (aBlocked.length > 5 ? " …" : "")]));
      }
      this._countSelected();
    },

    _countSelected: function () {
      var oView = this.getView().getModel("view");
      var iCount = (oView.getProperty("/forms") || []).filter(function (f) { return f.selected && !f.InMigration; }).length;
      oView.setProperty("/selectedCount", iCount);
    },

    onOpenMigrationFromForm: function (oEvent) {
      var oForm = oEvent.getSource().getBindingContext("view").getObject();
      if (oForm.MigUuid) {
        this.router().navTo("detail", { migUuid: oForm.MigUuid });
      }
    },

    // ------------------------------------------------------- commit selection
    onNext: async function () {
      var oView = this.getView().getModel("view");
      var aSelected = (oView.getProperty("/forms") || []).filter(function (f) { return f.selected && !f.InMigration; });
      if (!aSelected.length) { return; }
      oView.setProperty("/commit", {
        phase: "confirm",
        items: aSelected.map(function (f) {
          return {
            FormName: f.FormName, Description: f.Description, SerialNo: null, MigUuid: null,
            state: "", resultText: this.i18n("readyToCommit"), resultState: "None"
          };
        }.bind(this))
      });
      var oDialog = await this._dialog("commitDialog", "vernasoft.boltfiori.fragment.CommitDialog");
      oDialog.open();
    },

    onCommitEscape: function (oPromise) {
      if (this.getView().getModel("view").getProperty("/commit/phase") === "sending") {
        oPromise.reject();
      } else {
        oPromise.resolve();
      }
    },

    onCommitClose: function () {
      var oView = this.getView().getModel("view");
      this.byId("commitDialog").close();
      if (oView.getProperty("/commit/phase") === "done") {
        this._loadForms();
        this._loadMigrations();
      }
    },

    onCommitPrimary: function () {
      var oView = this.getView().getModel("view");
      if (oView.getProperty("/commit/phase") === "confirm") {
        this._commitSelection();
      } else {
        this.byId("commitDialog").close();
        oView.setProperty("/tab", "migration");
        this._loadForms();
        this._loadMigrations();
      }
    },

    _commitSelection: async function () {
      var oView = this.getView().getModel("view");
      var oService = this.service();
      var aItems = oView.getProperty("/commit/items");
      oView.setProperty("/commit/phase", "sending");
      aItems.forEach(function (it) { it.state = "busy"; it.resultText = this.i18n("committing"); it.resultState = "None"; }.bind(this));
      oView.refresh(true);

      // 1. one commit: the rows get their serial numbers (forms already in migration are skipped)
      var aCreated;
      try {
        aCreated = await oService.listAction("/Migration", "commitSelection", {
          SystemId: oView.getProperty("/systemId"),
          Selection: aItems.map(function (it) {
            return it.FormName + "|" + String(it.Description || "").replace(/[|\r\n]/g, " ");
          }).join("\n")
        });
      } catch (e) {
        oView.setProperty("/commit/phase", "confirm");
        aItems.forEach(function (it) { it.state = ""; it.resultText = ""; });
        oView.refresh(true);
        this.showError(e);
        return;
      }
      var aSkipped = oService.drainMessages().filter(function (m) { return m.type === "Warning"; });

      aItems.forEach(function (it) {
        var oRow = aCreated.find(function (c) { return c.FormName === it.FormName; });
        if (oRow) {
          it.MigUuid = oRow.MigUuid;
          it.SerialNo = oRow.SerialNo;
          it.resultText = this.i18n("waitingToSend");
        } else {
          it.state = "";
          it.resultState = "Warning";
          var oMsg = aSkipped.find(function (m) { return m.text.indexOf(it.FormName) === 0; });
          it.resultText = oMsg ? oMsg.text : this.i18n("notCommitted");
        }
      }.bind(this));
      oView.refresh(true);

      // 2. each form to GitHub, one after the other (legacy grab + XML + drivers + status file)
      for (var i = 0; i < aItems.length; i++) {
        var it = aItems[i];
        if (!it.MigUuid) { continue; }
        it.resultText = this.i18n("sendingToGithub");
        oView.refresh(true);
        try {
          var oResult = await oService.action("/Migration(MigUuid=" + it.MigUuid + ")", "pushToGitHub", {});
          oService.drainMessages();
          if (oResult && oResult.PushStatus === "PUSHED") {
            it.resultState = "Success";
            it.resultText = this.i18n("sentToGithub", [oResult.FilesPushed || 0]);
          } else {
            it.resultState = "Error";
            it.resultText = (oResult && oResult.PushMessage) || this.i18n("sendFailed");
          }
        } catch (e) {
          it.resultState = "Error";
          it.resultText = oService.errorText(e);
        }
        it.state = "";
        oView.refresh(true);
      }

      oView.setProperty("/commit/phase", "done");
      (oView.getProperty("/forms") || []).forEach(function (f) { f.selected = false; });
      this._countSelected();
      oView.refresh(true);
    },

    // --------------------------------------------------------------- migrations
    _loadMigrations: async function () {
      var oView = this.getView().getModel("view");
      oView.setProperty("/migBusy", true);
      try {
        var aRows = await this.service().list("/Migration", { sorters: [new Sorter("SerialNo", true)] });
        aRows.forEach(function (m) {
          m.statusText = formatter.statusText(m);
          m.statusState = formatter.statusState(m);
          m.needsClient = formatter.needsClient(m);
          m.ageText = formatter.ageText(m);
          m.ageState = formatter.ageState(m);
        });
        oView.setProperty("/migrations", aRows);
      } catch (e) {
        this.showError(e);
      } finally {
        oView.setProperty("/migBusy", false);
      }
      this._applyMigrationFilter();
    },

    _refreshStatuses: async function (bQuiet) {
      var oView = this.getView().getModel("view");
      oView.setProperty("/migBusy", true);
      try {
        await this.service().action("/Migration", "refreshAll", {});
        if (bQuiet) {
          this.service().drainMessages();
        } else {
          this.showMessages(this.i18n("statusesRefreshed"));
        }
        this.appModel().setProperty("/lastRefresh", new Date());
      } catch (e) {
        if (!bQuiet) { this.showError(e); }
      } finally {
        oView.setProperty("/migBusy", false);
      }
      await this._loadMigrations();
    },

    onRefreshStatuses: function () {
      this._refreshStatuses(false);
    },

    onImport: async function () {
      await this.withBusy(async function () {
        var aImported = await this.service().listAction("/Migration", "importFromGitHub", {});
        this.showMessages(this.i18n("imported", [aImported.length]));
      }.bind(this));
      this._loadMigrations();
      this._loadForms();
    },

    onMigrationSearch: function () { this._applyMigrationFilter(); },
    onMigrationFilter: function () { this._applyMigrationFilter(); },

    _applyMigrationFilter: function () {
      var oView = this.getView().getModel("view");
      var aAll = oView.getProperty("/migrations") || [];
      var sFilter = oView.getProperty("/migFilter");
      var sSearch = (oView.getProperty("/migSearch") || "").trim().toUpperCase();
      var bWithdrawn = oView.getProperty("/showWithdrawn");
      var aActive = aAll.filter(function (m) { return m.Withdrawn !== "X"; });

      var isProblem = function (m) { return m.PushStatus === "FAILED" || m.PushStatus === "PENDING" || m.StopFlag === "X"; };
      var isCompleted = function (m) { return m.Status === "completed"; };
      oView.setProperty("/kpi/total", aActive.length);
      oView.setProperty("/kpi/waiting", aActive.filter(function (m) { return m.needsClient; }).length);
      oView.setProperty("/kpi/completed", aActive.filter(isCompleted).length);
      oView.setProperty("/kpi/problems", aActive.filter(isProblem).length);
      oView.setProperty("/kpi/active", aActive.filter(function (m) {
        return !isCompleted(m) && !isProblem(m) && !m.needsClient;
      }).length);

      var aShown = (bWithdrawn ? aAll : aActive).filter(function (m) {
        if (sFilter === "needs" && !m.needsClient) { return false; }
        if (sFilter === "completed" && !isCompleted(m)) { return false; }
        if (sFilter === "problems" && !isProblem(m)) { return false; }
        if (sFilter === "active" && (isCompleted(m) || isProblem(m) || m.needsClient)) { return false; }
        if (!sSearch) { return true; }
        return [m.FormName, m.FormDescription, m.BranchName, m.statusText, m.StatusNote, String(m.SerialNo)].some(function (s) {
          return String(s || "").toUpperCase().indexOf(sSearch) >= 0;
        });
      });
      oView.setProperty("/migrationsShown", aShown);
    },

    onMigrationPress: function (oEvent) {
      var oMig = oEvent.getSource().getBindingContext("view").getObject();
      this.router().navTo("detail", { migUuid: oMig.MigUuid });
    },

    // ------------------------------------------------------------ configuration
    _resetConfig: function (oSetup) {
      var oConfig = {};
      CONFIG_FIELDS.forEach(function (sField) { oConfig[sField] = oSetup ? oSetup[sField] : ""; });
      oConfig.AiProvider = oConfig.AiProvider || "NONE";
      oConfig.AiMaxTokens = Number(oConfig.AiMaxTokens) || 2000;
      oConfig.countVolume = !!oSetup && oSetup.CountVolume === "X";
      var oView = this.getView().getModel("view");
      oView.setProperty("/config", oConfig);
      oView.setProperty("/aiKey", "");
    },

    _saveConfig: async function () {
      var oView = this.getView().getModel("view");
      var oSetup = this.appModel().getProperty("/setup") || {};
      var oConfig = Object.assign({}, oView.getProperty("/config"));
      oConfig.CountVolume = oConfig.countVolume ? "X" : "";
      oConfig.AiMaxTokens = Number(oConfig.AiMaxTokens) || 2000;
      var mChanges = {};
      CONFIG_FIELDS.forEach(function (sField) {
        var vNew = oConfig[sField] === undefined || oConfig[sField] === null ? "" : oConfig[sField];
        var vOld = oSetup[sField] === undefined || oSetup[sField] === null ? "" : oSetup[sField];
        if (typeof vNew === "string") { vNew = vNew.trim(); }
        if (vNew !== vOld) { mChanges[sField] = vNew; }
      });
      if (Object.keys(mChanges).length) {
        await this.service().update("/Setup('DEFAULT')", mChanges);
      }
      var sKey = (oView.getProperty("/aiKey") || "").trim();
      if (sKey) {
        await this.service().action("/Setup('DEFAULT')", "setAiKey", { ApiKey: sKey });
      }
      this.service().drainMessages();
      var oNew = await this.loadSetup();
      this._resetConfig(oNew);
    },

    onSaveConfig: async function () {
      var oView = this.getView().getModel("view");
      oView.setProperty("/configMessage", "");
      await this.withBusy(async function () {
        await this._saveConfig();
        oView.setProperty("/configMessage", this.i18n("saved"));
        MessageToast.show(this.i18n("saved"));
      }.bind(this), "view>/configBusy");
    },

    onTestAi: async function () {
      await this.withBusy(async function () {
        await this._saveConfig();
        await this.service().action("/Setup('DEFAULT')", "testAi", {});
        this.showMessages();
        this._resetConfig(await this.loadSetup());
      }.bind(this), "view>/configBusy");
    },

    onTestGitHub: async function () {
      await this.withBusy(async function () {
        await this._saveConfig();
        await this.service().action("/Setup('DEFAULT')", "testGitHub", {});
        this.showMessages();
        this._resetConfig(await this.loadSetup());
      }.bind(this), "view>/configBusy");
    },

    // ------------------------------------------------------------- SAP systems
    onAddSystem: async function () {
      this.getView().getModel("view").setProperty("/systemEdit", {
        isNew: true, SystemId: "", Description: "", SapClient: "", Destination: "",
        ServicePath: "/sap/opu/odata4/sap/zbolt_ui_o4/srvd/sap/zbolt_ui/0001/", BaseUrl: "",
        SortOrder: ((this.appModel().getProperty("/systems") || []).length + 1) * 10, local: false, default: false
      });
      (await this._dialog("systemDialog", "vernasoft.boltfiori.fragment.SystemDialog")).open();
    },

    onEditSystem: async function (oEvent) {
      var oSys = oEvent.getSource().getBindingContext("app").getObject();
      this.getView().getModel("view").setProperty("/systemEdit", Object.assign({}, oSys, {
        isNew: false, local: oSys.IsLocal === "X", default: oSys.IsDefault === "X"
      }));
      (await this._dialog("systemDialog", "vernasoft.boltfiori.fragment.SystemDialog")).open();
    },

    onCancelSystem: function () {
      this.byId("systemDialog").close();
    },

    onSaveSystem: async function () {
      var oEdit = this.getView().getModel("view").getProperty("/systemEdit");
      var sId = String(oEdit.SystemId || "").trim().toUpperCase();
      if (!sId) {
        MessageBox.warning(this.i18n("sysIdRequired"));
        return;
      }
      if (!oEdit.local && !String(oEdit.Destination || "").trim()) {
        MessageBox.warning(this.i18n("sysDestRequired"));
        return;
      }
      var oData = {
        Description: String(oEdit.Description || "").trim(),
        SapClient: String(oEdit.SapClient || "").trim(),
        Destination: oEdit.local ? "" : String(oEdit.Destination || "").trim().toUpperCase(),
        ServicePath: String(oEdit.ServicePath || "").trim(),
        BaseUrl: String(oEdit.BaseUrl || "").trim(),
        IsLocal: oEdit.local ? "X" : "",
        IsDefault: oEdit.default ? "X" : "",
        SortOrder: Number(oEdit.SortOrder) || 0
      };
      await this.withBusy(async function () {
        if (oEdit.isNew) {
          await this.service().create("/SourceSystem", Object.assign({ SystemId: sId }, oData));
        } else {
          await this.service().update("/SourceSystem('" + sId + "')", oData);
        }
        // Only one default system.
        if (oData.IsDefault === "X") {
          var aOthers = (this.appModel().getProperty("/systems") || []).filter(function (s) {
            return s.SystemId !== sId && s.IsDefault === "X";
          });
          for (var i = 0; i < aOthers.length; i++) {
            await this.service().update("/SourceSystem('" + aOthers[i].SystemId + "')", { IsDefault: "" });
          }
        }
        this.byId("systemDialog").close();
        await this.service().action("/SourceSystem('" + sId + "')", "testConnection", {});
        this.showMessages();
        await this.loadSetup();
        this.updateReadiness(this.getView().getModel("view").getProperty("/systemId"));
      }.bind(this));
    },

    onDeleteSystem: function (oEvent) {
      var oSys = oEvent.getSource().getBindingContext("app").getObject();
      MessageBox.confirm(this.i18n("deleteSystemConfirm", [oSys.SystemId]), {
        onClose: async function (sAction) {
          if (sAction !== MessageBox.Action.OK) { return; }
          await this.withBusy(async function () {
            await this.service().remove("/SourceSystem('" + oSys.SystemId + "')");
            await this.loadSetup();
          }.bind(this));
        }.bind(this)
      });
    },

    onTestSystem: async function (oEvent) {
      var oSys = oEvent.getSource().getBindingContext("app").getObject();
      await this.withBusy(async function () {
        await this.service().action("/SourceSystem('" + oSys.SystemId + "')", "testConnection", {});
        this.showMessages();
        await this.loadSetup();
        this.updateReadiness(this.getView().getModel("view").getProperty("/systemId"));
      }.bind(this));
      if (oSys.SystemId === this.getView().getModel("view").getProperty("/systemId")) {
        this._loadForms();
      }
    },

    // ---------------------------------------------------------------- helpers
    _dialog: async function (sId, sFragment) {
      this._mDialogs = this._mDialogs || {};
      if (!this._mDialogs[sId]) {
        this._mDialogs[sId] = await Fragment.load({ id: this.getView().getId(), name: sFragment, controller: this });
        this.getView().addDependent(this._mDialogs[sId]);
      }
      return this._mDialogs[sId];
    }
  });
});
