sap.ui.define([
  "vernasoft/boltfiori/controller/BaseController"
], function (BaseController) {
  "use strict";

  return BaseController.extend("vernasoft.boltfiori.controller.App", {
    onInit: function () {
      this.getView().addStyleClass(this.getOwnerComponent().getContentDensityClass
        ? this.getOwnerComponent().getContentDensityClass()
        : "sapUiSizeCompact");
    }
  });
});
