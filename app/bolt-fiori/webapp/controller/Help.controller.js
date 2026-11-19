sap.ui.define([
  "vernasoft/boltfiori/controller/BaseController",
  "sap/ui/model/json/JSONModel"
], function (BaseController, JSONModel) {
  "use strict";

  /** Help page: reads webapp/help/help.html and splits it at its "section:<id>|<title>" markers. */
  return BaseController.extend("vernasoft.boltfiori.controller.Help", {

    onInit: function () {
      this.getView().setModel(new JSONModel({ sections: [], shown: [], current: "", html: "", search: "", index: 0, count: 0 }), "help");
      this.router().getRoute("help").attachPatternMatched(this._onMatched, this);
    },

    _onMatched: async function (oEvent) {
      var sSection = (oEvent.getParameter("arguments") || {}).section;
      await this._load();
      this._show(sSection || this.getView().getModel("help").getProperty("/current") || "process");
    },

    _load: async function () {
      var oModel = this.getView().getModel("help");
      if (oModel.getProperty("/sections").length) { return; }
      var sText = "";
      try {
        var oResponse = await fetch(sap.ui.require.toUrl("vernasoft/boltfiori/help/help.html"));
        sText = await oResponse.text();
      } catch (e) {
        sText = "<!-- section:process|Help --><p>" + this.i18n("helpNotLoaded") + "</p>";
      }
      var aSections = [];
      var re = /<!--\s*section:([\w-]+)\|([^>]*?)\s*-->/g;
      var aMarks = [];
      var m;
      while ((m = re.exec(sText)) !== null) {
        aMarks.push({ id: m[1], title: m[2], start: m.index, end: m.index + m[0].length });
      }
      aMarks.forEach(function (oMark, i) {
        var sHtml = sText.slice(oMark.end, i + 1 < aMarks.length ? aMarks[i + 1].start : sText.length).trim();
        aSections.push({ id: oMark.id, title: oMark.title, html: sHtml, plain: sHtml.replace(/<[^>]+>/g, " ").toLowerCase(), hits: 0 });
      });
      oModel.setProperty("/sections", aSections);
      oModel.setProperty("/shown", aSections);
      oModel.setProperty("/count", aSections.length);
    },

    _show: function (sId) {
      var oModel = this.getView().getModel("help");
      var aSections = oModel.getProperty("/sections");
      var iIndex = Math.max(0, aSections.findIndex(function (s) { return s.id === sId; }));
      var oSection = aSections[iIndex];
      if (!oSection) { return; }
      var sHtml = oSection.html;
      var sSearch = (oModel.getProperty("/search") || "").trim();
      if (sSearch.length > 1) {
        // Mark the search term in the text (outside of tags).
        var reTerm = new RegExp("(" + sSearch.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")(?![^<]*>)", "gi");
        sHtml = sHtml.replace(reTerm, "<strong>$1</strong>");
      }
      oModel.setProperty("/current", oSection.id);
      oModel.setProperty("/index", iIndex);
      oModel.setProperty("/html", sHtml);
      var oPage = this.byId("helpPage");
      if (oPage) { oPage.scrollTo(0, 0); }
    },

    onSelect: function (oEvent) {
      var oCtx = oEvent.getParameter("listItem").getBindingContext("help");
      this._show(oCtx.getProperty("id"));
    },

    onSearch: function () {
      var oModel = this.getView().getModel("help");
      var sSearch = (oModel.getProperty("/search") || "").trim().toLowerCase();
      var aSections = oModel.getProperty("/sections");
      aSections.forEach(function (s) {
        s.hits = sSearch.length > 1 ? s.plain.split(sSearch).length - 1 : 0;
      });
      var aShown = sSearch.length > 1 ? aSections.filter(function (s) { return s.hits > 0 || s.title.toLowerCase().indexOf(sSearch) >= 0; }) : aSections;
      oModel.setProperty("/shown", aShown);
      if (aShown.length) {
        this._show(aShown.some(function (s) { return s.id === oModel.getProperty("/current"); }) ? oModel.getProperty("/current") : aShown[0].id);
      }
    },

    onPrev: function () {
      var oModel = this.getView().getModel("help");
      this._show(oModel.getProperty("/sections")[oModel.getProperty("/index") - 1].id);
    },

    onNext: function () {
      var oModel = this.getView().getModel("help");
      this._show(oModel.getProperty("/sections")[oModel.getProperty("/index") + 1].id);
    },

    onNavBack: function () {
      if (window.history.length > 1) {
        window.history.go(-1);
      } else {
        this.router().navTo("dashboard", {}, true);
      }
    }
  });
});
