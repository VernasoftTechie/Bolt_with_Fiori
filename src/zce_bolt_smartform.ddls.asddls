@EndUserText.label: 'Bolt - Smart Forms overview'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_BOLT_Q_SMARTFORM'

// Smart Forms of the selected source system (filter SystemId), merged with
// this app's own migration table so a form already in migration can't be
// selected twice. Read-only, served by the query class. A row with FormName
// '*ERROR*' carries the reason the list could not be read in Message.

define custom entity ZCE_BOLT_SMARTFORM
{
      @EndUserText.label: 'System'
  key SystemId        : abap.char( 10 );
      @EndUserText.label: 'Smart Form'
  key FormName        : abap.char( 30 );
      @EndUserText.label: 'Description'
      Description     : abap.char( 80 );
      @EndUserText.label: 'Package'
      DevPackage      : abap.char( 30 );
      @EndUserText.label: 'Created by'
      CreatedBy       : abap.char( 12 );
      @EndUserText.label: 'Created on (YYYYMMDD)'
      CreatedOn       : abap.char( 8 );
      @EndUserText.label: 'Changed by'
      ChangedBy       : abap.char( 12 );
      @EndUserText.label: 'Changed on (YYYYMMDD)'
      ChangedOn       : abap.char( 8 );
      @EndUserText.label: 'Driver program (NACE)'
      DriverProgram   : abap.char( 40 );
      @EndUserText.label: 'Output types (NACE)'
      OutputTypes     : abap.char( 120 );
      @EndUserText.label: 'In migration'
      InMigration     : abap_boolean;
      @EndUserText.label: 'Serial number'
      MigrationSerial : abap.int4;
      @EndUserText.label: 'Migration status'
      MigrationStatus : abap.char( 60 );
      @EndUserText.label: 'Migration'
      MigUuid         : sysuuid_x16;
      @EndUserText.label: 'Message'
      Message         : abap.char( 255 );
}
