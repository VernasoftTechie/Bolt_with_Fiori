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

      // Shared app state: connection readiness (the header indicator and the
      // gate on "Next"), the setup row and the source systems. Every view reads
      // it as model "app"; the OData V4 model is named "odata" (Playbook U1).
      this.setModel(new JSONModel({
        busy: false,
        customer: "",
        isAdmin: true,
        setup: {},
        systems: [],
        ready: { github: false, ai: false, system: false, all: false },
        lastRefresh: null,
        autoRefresh: false
      }), "app");

      this.service = service.create(this.getModel("odata"));
      this.getRouter().initialize();
    },

    getService: function () {
      return this.service;
    }
  });
});
