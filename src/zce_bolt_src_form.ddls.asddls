@EndUserText.label: 'Bolt - Smart Forms of this system (source API)'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_BOLT_Q_SRC_FORM'

// Machine-to-machine: the Bolt app on another system (DEV/QA/PRD) reads this
// system's Smart Form list through it. Element names are upper case on
// purpose - they map 1:1 onto the ABAP structure the calling system parses.
// Optional filter PREFIXES eq 'Z,Y' sets the custom name prefixes.

define custom entity ZCE_BOLT_SRC_FORM
{
      @EndUserText.label: 'Smart Form'
  key FORM_NAME      : abap.char( 30 );
      @EndUserText.label: 'Description'
      DESCRIPTION    : abap.char( 80 );
      @EndUserText.label: 'Package'
      DEV_PACKAGE    : abap.char( 30 );
      @EndUserText.label: 'Created by'
      CREATED_BY     : abap.char( 12 );
      @EndUserText.label: 'Created on'
      CREATED_ON     : abap.char( 8 );
      @EndUserText.label: 'Changed by'
      CHANGED_BY     : abap.char( 12 );
      @EndUserText.label: 'Changed on'
      CHANGED_ON     : abap.char( 8 );
      @EndUserText.label: 'Driver program'
      DRIVER_PROGRAM : abap.char( 40 );
      @EndUserText.label: 'Output types'
      OUTPUT_TYPES   : abap.char( 120 );
      @EndUserText.label: 'Prefixes (filter only)'
      PREFIXES       : abap.char( 20 );
}
