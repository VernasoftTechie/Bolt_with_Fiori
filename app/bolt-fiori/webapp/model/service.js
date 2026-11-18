sap.ui.define([
  "sap/ui/core/Messaging"
], function (Messaging) {
  "use strict";

  // RAP OData V4 operation namespace = com.sap.gateway.srvd.<service definition>.v<version>
  var NS = "com.sap.gateway.srvd.zbolt_ui.v0001";
  var iGroup = 0;

  function errorText(oError) {
    if (!oError) { return "Unknown error"; }
    if (oError.error && oError.error.message) { return oError.error.message; }
    return oError.message || String(oError);
  }

  function create(oModel) {
    return {
      ns: NS,
      errorText: errorText,

      /** Reads a whole entity set page by page (gateways cap pages below $top - Playbook U7). */
      list: async function (sPath, mOptions) {
        var mOpt = mOptions || {};
        var oBinding = oModel.bindList(sPath, null, mOpt.sorters || [], mOpt.filters || [],
          Object.assign({ $count: true }, mOpt.parameters || {}));
        var aAll = [];
        var iStart = 0;
        try {
          for (var i = 0; i < 200; i++) {
            var aContexts = await oBinding.requestContexts(iStart, 500);
            aContexts.forEach(function (oCtx) { aAll.push(oCtx.getObject()); });
            iStart += aContexts.length;
            var iCount = oBinding.getCount();
            if (!aContexts.length || (iCount !== undefined && iStart >= iCount)) { break; }
          }
        } finally {
          oBinding.destroy();
        }
        return aAll;
      },

      object: async function (sPath, mParameters) {
        var oBinding = oModel.bindContext(sPath, null, mParameters || {});
        try {
          return await oBinding.requestObject();
        } finally {
          oBinding.destroy();
        }
      },

      /**
       * Runs an action. sPath = "/Migration(MigUuid=...)" for an instance action,
       * "/Migration" for a static (collection-bound) one. Returns the result payload:
       * the entity for "result [1] $self", { value: [...] } for a collection.
       */
      action: async function (sPath, sAction, mParameters) {
        var oBinding = oModel.bindContext(sPath + "/" + NS + "." + sAction + "(...)");
        Object.keys(mParameters || {}).forEach(function (sName) {
          oBinding.setParameter(sName, mParameters[sName]);
        });
        try {
          await oBinding.execute();
          var oResult = oBinding.getBoundContext();
          return oResult ? await oResult.requestObject() : null;
        } finally {
          oBinding.destroy();
        }
      },

      /** Same, for a static action whose result is a list - always returns an array. */
      listAction: async function (sPath, sAction, mParameters) {
        var vResult = await this.action(sPath, sAction, mParameters);
        if (Array.isArray(vResult)) { return vResult; }
        return (vResult && vResult.value) || [];
      },

      /** PATCH of the given properties; rejects with the backend's message if refused. */
      update: async function (sPath, mChanges) {
        var sGroup = "bolt" + (++iGroup);
        var oBinding = oModel.bindContext(sPath, null, { $$updateGroupId: sGroup });
        try {
          await oBinding.requestObject();
          var oContext = oBinding.getBoundContext();
          var aPromises = Object.keys(mChanges).map(function (sName) {
            return oContext.setProperty(sName, mChanges[sName], sGroup);
          });
          oModel.submitBatch(sGroup);
          await Promise.all(aPromises);
        } catch (oError) {
          oModel.resetChanges(sGroup);
          throw oError;
        } finally {
          oBinding.destroy();
        }
      },

      create: async function (sPath, oData) {
        var sGroup = "bolt" + (++iGroup);
        var oBinding = oModel.bindList(sPath, null, [], [], { $$updateGroupId: sGroup });
        var oContext = oBinding.create(oData);
        try {
          oModel.submitBatch(sGroup);
          await oContext.created();
          return oContext.getObject();
        } catch (oError) {
          oModel.resetChanges(sGroup);
          throw oError;
        } finally {
          oBinding.destroy();
        }
      },

      remove: async function (sPath) {
        var oBinding = oModel.bindContext(sPath);
        try {
          await oBinding.requestObject();
          await oBinding.getBoundContext().delete("$auto");
        } finally {
          oBinding.destroy();
        }
      },

      /** Messages RAP sent along (success/info/warning), then cleared. */
      drainMessages: function () {
        var aMessages = (Messaging.getMessageModel().getData() || []).map(function (oMessage) {
          return { type: oMessage.getType(), text: oMessage.getMessage() };
        });
        Messaging.removeAllMessages();
        return aMessages;
      }
    };
  }

  return { create: create, errorText: errorText, NS: NS };
});
