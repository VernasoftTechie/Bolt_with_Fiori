sap.ui.define([
  "sap/ui/core/UIComponent",
  "sap/ui/model/json/JSONModel",
  "vernasoft/boltfiori/model/service"
], function (UIComponent, JSONModel, service) {
  "use strict";

  return UIComponent.extend("vernasoft.boltfiori.Component", {
    metadata: { manifest: "json" },

    init: function () {
      UIComponent.prototype.init.apply(this, arguments);

      // Shared app state: the system the app runs in (no system selection -
      // the logged-on system is the source of the Smart Forms), the setup row
      // and the connection readiness (header chips, LIVE, the gate on "Next").
      // Every view reads it as model "app"; the OData V4 model is "odata".
      this.setModel(new JSONModel({
        busy: false,
        sys: {},
        setup: {},
        isAdmin: false,
        sysError: "",
        setupError: "",
        ready: { github: false, repo: false, ai: false, all: false }
      }), "app");

      this.service = service.create(this.getModel("odata"));
      this.getRouter().initialize();
    },

    getService: function () {
      return this.service;
    }
  });
});
