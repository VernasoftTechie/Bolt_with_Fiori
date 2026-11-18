sap.ui.define([
  "sap/ui/core/mvc/Controller",
  "sap/m/MessageToast",
  "sap/m/MessageBox",
  "vernasoft/boltfiori/model/formatter",
  "sap/ui/model/Sorter"
], function (Controller, MessageToast, MessageBox, formatter, Sorter) {
  "use strict";

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

    /** Runs fnWork with the app busy; shows the backend's message on failure. */
    withBusy: async function (fnWork, sBusyPath) {
      var oModel = sBusyPath ? this.getView().getModel(sBusyPath.split(">")[0]) : this.appModel();
      var sPath = sBusyPath ? sBusyPath.split(">")[1] : "/busy";
      oModel.setProperty(sPath, true);
      try {
        return await fnWork();
      } catch (oError) {
        this.showError(oError);
        return undefined;
      } finally {
        oModel.setProperty(sPath, false);
      }
    },

    showError: function (oError) {
      var aMessages = this.service().drainMessages().filter(function (m) { return m.type === "Error"; });
      var sText = aMessages.length ? aMessages.map(function (m) { return m.text; }).join("\n") : this.service().errorText(oError);
      MessageBox.error(sText);
    },

    /** Shows the success/information/warning messages RAP returned with the last call. */
    showMessages: function (sFallback) {
      var aMessages = this.service().drainMessages();
      var aWarnings = aMessages.filter(function (m) { return m.type === "Warning" || m.type === "Error"; });
      if (aWarnings.length) {
        MessageBox.warning(aWarnings.map(function (m) { return m.text; }).join("\n"));
        return;
      }
      var sText = aMessages.length ? aMessages.map(function (m) { return m.text; }).join("\n") : sFallback;
      if (sText) {
        MessageToast.show(sText, { duration: 5000, width: "30rem" });
      }
    },

    /** Loads the setup row (creating it on first start) and the source systems. */
    loadSetup: async function () {
      var oService = this.service();
      var oSetup;
      try {
        oSetup = await oService.object("/Setup('DEFAULT')");
      } catch (e) {
        oSetup = null;
      }
      if (!oSetup) {
        oSetup = await oService.action("/Setup", "initialize", {});
      }
      var aSystems = await oService.list("/SourceSystem", {
        sorters: [new Sorter("SortOrder"), new Sorter("SystemId")]
      });
      var oApp = this.appModel();
      oApp.setProperty("/setup", oSetup || {});
      oApp.setProperty("/customer", (oSetup && oSetup.CustomerName) || "");
      oApp.setProperty("/systems", aSystems);
      oApp.setProperty("/isAdmin", this.isAdmin(oSetup));
      this.updateReadiness();
      return oSetup;
    },

    isAdmin: function (oSetup) {
      var sList = ((oSetup && oSetup.AdminUsers) || "").trim().toUpperCase();
      if (!sList) { return true; }
      // In the Fiori launchpad the user is known; standalone, the backend decides.
      try {
        var sUser = sap.ushell && sap.ushell.Container && sap.ushell.Container.getUser().getId().toUpperCase();
        if (sUser) {
          return sList.split(",").map(function (s) { return s.trim(); }).indexOf(sUser) >= 0;
        }
      } catch (e) { /* not in the launchpad */ }
      return true;
    },

    /** Same gate as Bolt Console: SAP source system, GitHub and AI must be connected. */
    updateReadiness: function (sSystemId) {
      var oApp = this.appModel();
      var oSetup = oApp.getProperty("/setup") || {};
      var aSystems = oApp.getProperty("/systems") || [];
      var sId = sSystemId || oApp.getProperty("/selectedSystem");
      var oSystem = aSystems.find(function (s) { return s.SystemId === sId; }) ||
        aSystems.find(function (s) { return s.IsDefault === "X"; }) || aSystems[0];
      var bGithub = oSetup.GhStatus === "OK";
      var bAi = !oSetup.AiProvider || oSetup.AiProvider === "NONE" || oSetup.AiStatus === "OK";
      var bSystem = !!oSystem && oSystem.Status === "OK";
      oApp.setProperty("/ready", { github: bGithub, ai: bAi, system: bSystem, all: bGithub && bAi && bSystem });
    }
  });
});
