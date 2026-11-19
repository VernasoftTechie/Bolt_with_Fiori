@EndUserText.label: 'Bolt - Smart Forms of this system'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_AB_BOLT_Q_FORM'

// Every custom Smart Form of the system the app is launched in, merged with
// the migration table: MigState NONE (never selected), ACTIVE (in migration -
// cannot be selected again), STOPPED (stopped - can be selected again for a
// re-process run), COMPLETED (delivered - cannot be selected again).
// Read-only, served by the query class. Supports $filter on MigState and
// Selectable, $search on name/description/package, $orderby, paging, $count.

define custom entity ZAB_CDS_CE_BOLT_FORM
{
      @EndUserText.label: 'Smart Form'
  key FormName     : tdsfname;
      @EndUserText.label: 'Description'
      Description  : abap.char( 80 );
      @EndUserText.label: 'Package'
      DevPackage   : devclass;
      @EndUserText.label: 'Created by'
      CreatedBy    : syuname;
      @EndUserText.label: 'Created on'
      CreatedOn    : abap.dats;
      @EndUserText.label: 'Changed by'
      ChangedBy    : syuname;
      @EndUserText.label: 'Changed on'
      ChangedOn    : abap.dats;
      @EndUserText.label: 'Driver programs'
      DriverProgs  : abap.char( 255 );
      @EndUserText.label: 'Output types'
      OutputTypes  : abap.char( 255 );
      @EndUserText.label: 'Migration state'
      MigState     : abap.char( 10 );
      @EndUserText.label: 'Can be selected'
      Selectable   : abap_boolean;
      @EndUserText.label: 'Serial number'
      LastSerialNo : abap.int4;
      @EndUserText.label: 'Run'
      LastRunNo    : abap.int4;
      @EndUserText.label: 'Status'
      LastStatus   : abap.char( 30 );
      @EndUserText.label: 'Migration'
      LastMigUuid  : sysuuid_x16;
}
