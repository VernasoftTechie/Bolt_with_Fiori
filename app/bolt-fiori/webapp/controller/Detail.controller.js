sap.ui.define([
  "vernasoft/boltfiori/controller/BaseController",
  "sap/ui/model/json/JSONModel",
  "sap/ui/core/Fragment",
  "sap/ui/core/routing/History",
  "sap/m/MessageBox",
  "sap/m/MessageToast",
  "sap/m/Dialog",
  "sap/m/Button",
  "sap/m/FormattedText",
  "vernasoft/boltfiori/model/formatter"
], function (BaseController, JSONModel, Fragment, History, MessageBox, MessageToast, Dialog, Button, FormattedText, formatter) {
  "use strict";

  var MAX_FILE_BYTES = 20 * 1024 * 1024;

  return BaseController.extend("vernasoft.boltfiori.controller.Detail", {

    onInit: function () {
      this.getView().setModel(new JSONModel(this._empty()), "d");
      this.router().getRoute("detail").attachPatternMatched(this._onRouteMatched, this);
    },

    _empty: function () {
      return {
        busy: false, timeline: [], appLog: [], files: [],
        input: { text: "", fileName: "", fileContent: "" },
        reference: { fileName: "", fileContent: "" },
        stopNote: "", withdraw: { reason: "", deleteBranch: false }
      };
    },

    _onRouteMatched: function (oEvent) {
      this._sUuid = oEvent.getParameter("arguments").migUuid;
      this.getView().getModel("d").setData(this._empty());
      this._clearUploaders();
      if (!this.appModel().getProperty("/setup/SetupId")) {
        this.loadSetup().catch(function () { /* header chips only */ });
      }
      // Like the web app's status board: read the branch's status file every time the page opens.
      this._load(true);
    },

    _path: function () {
      return "/Migration(MigUuid=" + this._sUuid + ")";
    },

    _load: async function (bRefreshFromGithub) {
      var oD = this.getView().getModel("d");
      oD.setProperty("/busy", true);
      try {
        if (bRefreshFromGithub) {
          try {
            await this.service().action(this._path(), "refreshStatus", {});
            this.service().drainMessages();
          } catch (e) {
            // still show what is stored; the warning is in the app log/messages
          }
        }
        var oMig = await this.service().object(this._path(), { $expand: "_Log,_File" });
        this._setData(oMig);
      } catch (e) {
        this.showError(e);
      } finally {
        oD.setProperty("/busy", false);
      }
    },

    _setData: function (oMig) {
      var oD = this.getView().getModel("d");
      var oSetup = this.appModel().getProperty("/setup") || {};
      var aLogs = oMig._Log || [];
      var byTimeDesc = function (a, b) { return String(b.EntryAt).localeCompare(String(a.EntryAt)); };
      var sRepoUrl = oSetup.GhOwner && oSetup.GhRepo ? "https://github.com/" + oSetup.GhOwner + "/" + oSetup.GhRepo : "";
      var oKeep = oD.getData();

      var oData = Object.assign({}, oMig, {
        busy: false,
        statusText: formatter.statusText(oMig),
        statusState: formatter.statusState(oMig),
        needsClient: formatter.needsClient(oMig),
        systemText: oMig.SystemId + (oMig.SapClient ? " (client " + oMig.SapClient + ")" : ""),
        branchUrl: sRepoUrl && oMig.PushStatus === "PUSHED" ? sRepoUrl + "/tree/" + oMig.BranchName : "",
        hasConfirmedWork: oMig.Status === "completed" || aLogs.some(function (l) {
          return l.LogSource === "STATUS" && l.Heading === "Manual activity confirmed";
        }),
        // status file timeline: newest first (same order as the web app)
        timeline: aLogs.filter(function (l) { return l.LogSource === "STATUS"; })
          .sort(function (a, b) { return b.SeqNo - a.SeqNo; }),
        appLog: aLogs.filter(function (l) { return l.LogSource === "APP"; }).sort(byTimeDesc),
        files: (oMig._File || []).map(function (f) {
          return Object.assign({}, f, {
            url: sRepoUrl ? sRepoUrl + "/blob/" + oMig.BranchName + "/" + f.FilePath : ""
          });
        }).sort(function (a, b) { return String(a.FilePath).localeCompare(String(b.FilePath)); }),
        input: oKeep.input || { text: "", fileName: "", fileContent: "" },
        reference: oKeep.reference || { fileName: "", fileContent: "" },
        stopNote: oKeep.stopNote || "",
        withdraw: oKeep.withdraw || { reason: "", deleteBranch: false }
      });
      oD.setData(oData);
    },

    onNavBack: function () {
      if (History.getInstance().getPreviousHash() !== undefined) {
        window.history.go(-1);
      } else {
        this.router().navTo("dashboard", { tab: "migration" }, true);
      }
    },

    onRefresh: function () {
      this._load(true);
    },

    onOpenBranch: function () {
      var sUrl = this.getView().getModel("d").getProperty("/branchUrl");
      if (sUrl) { window.open(sUrl, "_blank", "noopener"); }
    },

    // ------------------------------------------------------------------ files
    onFileChosen: function (oEvent) {
      var oUploader = oEvent.getSource();
      var sSlot = oUploader.data("slot");
      var oD = this.getView().getModel("d");
      var oFile = (oEvent.getParameter("files") || [])[0];
      if (!oFile) {
        oD.setProperty("/" + sSlot + "/fileName", "");
        oD.setProperty("/" + sSlot + "/fileContent", "");
        return;
      }
      if (oFile.size > MAX_FILE_BYTES) {
        MessageBox.warning(this.i18n("fileTooLarge", [oFile.name]));
        oUploader.clear();
        return;
      }
      var oReader = new FileReader();
      oReader.onload = function () {
        var sDataUrl = String(oReader.result || "");
        oD.setProperty("/" + sSlot + "/fileName", oFile.name);
        oD.setProperty("/" + sSlot + "/fileContent", sDataUrl.substring(sDataUrl.indexOf(",") + 1));
      };
      oReader.readAsDataURL(oFile);
    },

    _clearUploaders: function () {
      this.getView().findAggregatedObjects(true, function (o) {
        return o.isA && o.isA("sap.ui.unified.FileUploader");
      }).forEach(function (o) { o.clear(); });
    },

    _resetInput: function () {
      var oD = this.getView().getModel("d");
      oD.setProperty("/input", { text: "", fileName: "", fileContent: "" });
      oD.setProperty("/reference", { fileName: "", fileContent: "" });
      oD.setProperty("/stopNote", "");
      this._clearUploaders();
    },

    // -------------------------------------------------------------- responses
    _run: async function (sAction, mParams, sDone) {
      var oD = this.getView().getModel("d");
      oD.setProperty("/busy", true);
      try {
        var oResult = await this.service().action(this._path(), sAction, mParams);
        this.showMessages(sDone);
        this._resetInput();
        if (oResult && oResult.MigUuid) {
          var oMig = await this.service().object(this._path(), { $expand: "_Log,_File" });
          this._setData(oMig);
        }
        return oResult;
      } catch (e) {
        this.showError(e);
        return null;
      } finally {
        oD.setProperty("/busy", false);
      }
    },

    onConfirm: function () {
      var oIn = this.getView().getModel("d").getProperty("/input");
      this._run("confirmManual", {
        Note: (oIn.text || "").trim(),
        FileName: oIn.fileName || "",
        FileContent: oIn.fileContent || ""
      }, this.i18n("confirmSent"));
    },

    onConcern: function (oEvent) {
      var sKind = oEvent.getSource().data("kind") || "concern";
      var oIn = this.getView().getModel("d").getProperty("/input");
      if (!(oIn.text || "").trim() && !oIn.fileContent) {
        MessageToast.show(this.i18n("typeConcernFirst"));
        return;
      }
      this._run("raiseConcern", {
        Kind: sKind,
        Text: (oIn.text || "").trim(),
        FileName: oIn.fileName || "",
        FileContent: oIn.fileContent || ""
      }, this.i18n("concernSent"));
    },

    onStop: function () {
      var sNote = (this.getView().getModel("d").getProperty("/stopNote") || "").trim();
      MessageBox.confirm(this.i18n("stopConfirm"), {
        onClose: function (sAction) {
          if (sAction === MessageBox.Action.OK) {
            this._run("setStop", { StopRequested: true, Note: sNote }, this.i18n("stopSent"));
          }
        }.bind(this)
      });
    },

    onResume: function () {
      this._run("setStop", { StopRequested: false, Note: "" }, this.i18n("resumed"));
    },

    onUploadReference: function () {
      var oRef = this.getView().getModel("d").getProperty("/reference");
      if (!oRef.fileContent) { return; }
      this._run("addReferenceFile", { FileName: oRef.fileName, FileContent: oRef.fileContent }, this.i18n("referenceUploaded"));
    },

    onRetrySend: function () {
      this._run("pushToGitHub", {}, this.i18n("sentToGithubShort"));
    },

    onAiSummary: async function () {
      var oD = this.getView().getModel("d");
      oD.setProperty("/busy", true);
      try {
        var oResult = await this.service().action(this._path(), "aiSummary", {});
        this.service().drainMessages();
        var oDialog = new Dialog({
          title: this.i18n("aiSummaryTitle", [oD.getProperty("/FormName")]),
          contentWidth: "40rem",
          content: [new FormattedText({ htmlText: formatter.markdown((oResult && oResult.ResultText) || "") })
            .addStyleClass("sapUiSmallMargin")],
          endButton: new Button({ text: this.i18n("close"), press: function () { oDialog.close(); } }),
          afterClose: function () { oDialog.destroy(); }
        });
        this.getView().addDependent(oDialog);
        oDialog.open();
        var oMig = await this.service().object(this._path(), { $expand: "_Log,_File" });
        this._setData(oMig);
      } catch (e) {
        this.showError(e);
      } finally {
        oD.setProperty("/busy", false);
      }
    },

    // ---------------------------------------------------------------- withdraw
    onWithdraw: async function () {
      this.getView().getModel("d").setProperty("/withdraw", { reason: "", deleteBranch: false });
      if (!this._oWithdraw) {
        this._oWithdraw = await Fragment.load({
          id: this.getView().getId(), name: "vernasoft.boltfiori.fragment.WithdrawDialog", controller: this
        });
        this.getView().addDependent(this._oWithdraw);
      }
      this._oWithdraw.open();
    },

    onWithdrawCancel: function () {
      this._oWithdraw.close();
    },

    onWithdrawConfirm: async function () {
      var oW = this.getView().getModel("d").getProperty("/withdraw");
      this._oWithdraw.close();
      var oResult = await this._run("withdraw", { DeleteBranch: !!oW.deleteBranch, Reason: (oW.reason || "").trim() },
        this.i18n("withdrawn"));
      if (oResult) {
        this.router().navTo("dashboard", { tab: "migration" }, true);
      }
    }
  });
});
