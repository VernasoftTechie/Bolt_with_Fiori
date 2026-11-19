sap.ui.define([
  "vernasoft/boltfiori/controller/BaseController",
  "sap/ui/model/json/JSONModel",
  "sap/m/MessageBox",
  "sap/m/MessageToast",
  "vernasoft/boltfiori/model/formatter",
  "sap/ui/model/Sorter"
], function (BaseController, JSONModel, MessageBox, MessageToast, formatter, Sorter) {
  "use strict";

  var DEFAULT_MODEL = { openai: "gpt-4o-mini", anthropic: "claude-sonnet-5-5", mock: "built-in" };
  var LIB_FOLDERS = { logo: "logos", smartstyle: "styles", naming_standard: "naming_standards", policy: "policies" };

  /**
   * Setup page: client, administrators, GitHub connection, AI provider, target
   * repository, global reference library, advanced settings. The same behaviour
   * as the web app's Configure page (docs/07_recheck_matrix.md, row 10).
   */
  return BaseController.extend("vernasoft.boltfiori.controller.Setup", {

    onInit: function () {
      this.getView().setModel(new JSONModel({
        cfg: {}, cfgBusy: false, token: "",
        ai: { Provider: "mock", Model: "", BaseUrl: "", MaxTokens: 4096, ApiKey: "", keySaved: false, blockedForKey: false,
              defaultModel: "built-in", currentText: "", testText: "", testOk: false },
        repo: { Repo: "", BranchPrefix: "", checkText: "", checkOk: false },
        lib: { Category: "logo", Provenance: "", files: [] },
        library: []
      }), "view");
      this.router().getRoute("setup").attachPatternMatched(this._onMatched, this);
      this.enableDropZones();
    },

    _onMatched: async function () {
      var that = this;
      await this.withBusy(async function () {
        await that.loadContext();
        that.fillConfig();
      }, "view", "/cfgBusy");
      this.loadLibrary();
    },

    onNavBack: function () { this.router().navTo("dashboard", {}, true); },

    onOpenHelp: function () { this.router().navTo("help", { section: "setup" }); },

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
      }, this.i18n("savedAdvanced"));
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

    /** Typing or pasting a key unlocks Test connection / Save at once (blockedForKey). */
    onAiKeyLive: function () { this._aiDerived(); },

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
