@EndUserText.label: 'Bolt - status file timeline (live)'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_AB_BOLT_Q_STATUS'

// The "## <time> - <heading>" entries of a migration's status file, read
// live from GitHub (not stored). Request with $filter=MigUuid eq <uuid>;
// EntryNo 1 = oldest. The full log of the process, engineer and client side.

define custom entity ZAB_CDS_CE_BOLT_TIMELN
{
      @EndUserText.label: 'Migration'
  key MigUuid   : sysuuid_x16;
      @EndUserText.label: 'Entry'
  key EntryNo   : abap.int4;
      @EndUserText.label: 'Time'
      EntryAt   : abap.char( 30 );
      @EndUserText.label: 'Heading'
      Heading   : abap.char( 120 );
      @EndUserText.label: 'Text'
      EntryText : abap.string( 0 );
}
