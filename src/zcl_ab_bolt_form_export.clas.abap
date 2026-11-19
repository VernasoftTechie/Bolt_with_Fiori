"! <p class="shorttext synchronized">Bolt - Smart Form + Smart Style export, complexity signal</p>
"! export_xml produces the same XML as SMARTFORMS > Utilities > Download
"! (function module FB_DOWNLOAD_FORM): load the form with
"! CL_SSF_FB_SMART_FORM, let it write itself into an iXML document, set the two
"! root namespaces, render as one line. This is the mechanism abapGit's own
"! Smart Form serializer (object type SSFO) uses. VERIFY ON FIRST USE: compare
"! one exported file against a manual download (docs/04_installation.md,
"! step "Smoke test") - the engineer's legacy-grab tool parses this file.
"!
"! export_style writes one Smart Style the way abapGit's SSST serializer reads
"! it (function module SSF_READ_STYLE: header, paragraphs, character strings,
"! tab stops of the active %MAIN variant) as an asXML document, so the engineer
"! sees every paragraph/character format the form uses without a manual
"! download. styles_used lists the custom styles a form's XML refers to.
"!
"! complexity is the ABAP port of Bolt Console's complexitySignal.js - a
"! structural first impression (windows, tables/loops, conditions, languages,
"! code nodes, graphics, interface size), never the real risk score.
CLASS zcl_ab_bolt_form_export DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_signal,
        ok         TYPE abap_bool,
        level      TYPE string,
        headline   TYPE string,
        windows    TYPE i,
        pages      TYPE i,
        graphics   TYPE i,
        code_nodes TYPE i,
        text_nodes TYPE i,
        tables     TYPE i,
        conditions TYPE i,
        languages  TYPE i,
        params     TYPE i,
      END OF ty_signal.

    CLASS-METHODS export_xml
      IMPORTING iv_formname   TYPE string
      RETURNING VALUE(rv_xml) TYPE string
      RAISING   zcx_ab_bolt.

    CLASS-METHODS complexity
      IMPORTING iv_xml           TYPE string
      RETURNING VALUE(rs_signal) TYPE ty_signal.

    "! Custom Smart Styles named in the form XML (STDSTYLE / STYLE_NAME elements,
    "! checked on a real export: ymmgrnnote.xml),
    "! sorted, without duplicates. Standard SAP styles (not Z/Y) are left out.
    CLASS-METHODS styles_used
      IMPORTING iv_xml           TYPE string
                iv_prefix1       TYPE string DEFAULT `Z`
                iv_prefix2       TYPE string DEFAULT `Y`
      RETURNING VALUE(rt_styles) TYPE string_table.

    "! The active %MAIN variant of a Smart Style as asXML (UTF-8 text).
    CLASS-METHODS export_style
      IMPORTING iv_style      TYPE string
                iv_language   TYPE spras DEFAULT sy-langu
      RETURNING VALUE(rv_xml) TYPE string
      RAISING   zcx_ab_bolt.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS band
      IMPORTING iv_value        TYPE i
                iv_low          TYPE i
                iv_high         TYPE i
      RETURNING VALUE(rv_score) TYPE i.
ENDCLASS.



CLASS zcl_ab_bolt_form_export IMPLEMENTATION.

  METHOD export_xml.
    DATA lo_form     TYPE REF TO cl_ssf_fb_smart_form.
    DATA lv_formname TYPE tdsfname.

    lv_formname = to_upper( condense( iv_formname ) ).

    DATA(lo_ixml) = cl_ixml=>create( ).
    DATA(lo_doc)  = lo_ixml->create_document( ).

    CREATE OBJECT lo_form.
    TRY.
        lo_form->load( im_formname = lv_formname
                       im_language = '' ).
      CATCH cx_ssf_fb INTO DATA(lx_load).
        RAISE EXCEPTION NEW zcx_ab_bolt(
          iv_text = |Smart Form { lv_formname } could not be loaded for export: { lx_load->get_text( ) }| ).
    ENDTRY.

    lo_form->xml_download( EXPORTING parent   = lo_doc
                           CHANGING  document = lo_doc ).

    DATA(lo_root) = lo_doc->get_root_element( ).
    IF lo_root IS NOT BOUND.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = |Smart Form { lv_formname } exported an empty XML document.| ).
    ENDIF.
    lo_root->set_attribute( name      = 'sf'
                            namespace = 'xmlns'
                            value     = 'urn:sap-com:SmartForms:2000:internal-structure' ).
    lo_root->set_attribute( name  = 'xmlns'
                            value = 'urn:sap-com:sdixml-ifr:2000' ).

    DATA(lo_stream) = lo_ixml->create_stream_factory( )->create_ostream_cstring( rv_xml ).
    DATA(lo_renderer) = lo_ixml->create_renderer( ostream  = lo_stream
                                                  document = lo_doc ).
    lo_renderer->set_normalizing( abap_false ).
    lo_renderer->render( ).

    " A string stream declares utf-16; the downloaded file (and GitHub) is UTF-8.
    REPLACE FIRST OCCURRENCE OF `encoding="utf-16"` IN rv_xml WITH `encoding="utf-8"` IGNORING CASE.
    IF find( val = rv_xml sub = `<?xml` ) <> 0.
      rv_xml = `<?xml version="1.0" encoding="utf-8"?>` && rv_xml.
    ENDIF.
  ENDMETHOD.


  METHOD styles_used.
    DATA lt_names TYPE string_table.

    FIND ALL OCCURRENCES OF REGEX '<(STDSTYLE|STYLE_NAME)>([^<]+)</(STDSTYLE|STYLE_NAME)>' IN iv_xml RESULTS DATA(lt_matches).
    LOOP AT lt_matches INTO DATA(ls_match).
      READ TABLE ls_match-submatches INTO DATA(ls_sub) INDEX 2.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      DATA(lv_name) = to_upper( condense( substring( val = iv_xml off = ls_sub-offset len = ls_sub-length ) ) ).
      IF lv_name IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(lv_first) = substring( val = lv_name len = 1 ).
      IF ( iv_prefix1 IS NOT INITIAL AND find( val = lv_name sub = to_upper( iv_prefix1 ) ) = 0 )
         OR ( iv_prefix2 IS NOT INITIAL AND find( val = lv_name sub = to_upper( iv_prefix2 ) ) = 0 )
         OR lv_first = `/`.
        APPEND lv_name TO lt_names.
      ENDIF.
    ENDLOOP.
    SORT lt_names.
    DELETE ADJACENT DUPLICATES FROM lt_names.
    rt_styles = lt_names.
  ENDMETHOD.


  METHOD export_style.
    DATA ls_header     TYPE ssfcats.
    DATA lt_paragraphs TYPE STANDARD TABLE OF ssfparas WITH DEFAULT KEY.
    DATA lt_strings    TYPE STANDARD TABLE OF ssfstrings WITH DEFAULT KEY.
    DATA lt_tabstops   TYPE STANDARD TABLE OF stxstab WITH DEFAULT KEY.
    DATA lv_style      TYPE tdssname.

    lv_style = to_upper( condense( iv_style ) ).
    CALL FUNCTION 'SSF_READ_STYLE'
      EXPORTING
        i_style_name             = lv_style
        i_style_active_flag      = 'A'
        i_style_variant          = '%MAIN'
        i_style_language         = iv_language
      IMPORTING
        e_header                 = ls_header
      TABLES
        e_paragraphs             = lt_paragraphs
        e_strings                = lt_strings
        e_tabstops               = lt_tabstops
      EXCEPTIONS
        no_name                  = 1
        no_style                 = 2
        active_style_not_found   = 3
        inactive_style_not_found = 4
        no_variant               = 5
        no_main_variant          = 6
        cancelled                = 7
        no_access_permission     = 8
        OTHERS                   = 9.
    IF sy-subrc <> 0.
      RAISE EXCEPTION NEW zcx_ab_bolt( iv_text = |Smart Style { lv_style } could not be read (SSF_READ_STYLE error { sy-subrc }).| ).
    ENDIF.

    CALL TRANSFORMATION id
      SOURCE header     = ls_header
             paragraphs = lt_paragraphs
             strings    = lt_strings
             tabstops   = lt_tabstops
      RESULT XML rv_xml.
    REPLACE FIRST OCCURRENCE OF `encoding="utf-16"` IN rv_xml WITH `encoding="utf-8"` IGNORING CASE.
  ENDMETHOD.


  METHOD band.
    rv_score = COND #( WHEN iv_value >= iv_high THEN 2
                       WHEN iv_value >= iv_low  THEN 1
                       ELSE 0 ).
  ENDMETHOD.


  METHOD complexity.
    DATA lt_langs TYPE string_table.

    IF find( val = iv_xml sub = `<sf:SMARTFORM` ) < 0.
      rs_signal-ok = abap_false.
      RETURN.
    ENDIF.
    rs_signal-ok = abap_true.

    rs_signal-windows    = count( val = iv_xml sub = `<NODETYPE>WI</NODETYPE>` ).
    rs_signal-pages      = count( val = iv_xml sub = `<NODETYPE>PA</NODETYPE>` ).
    rs_signal-graphics   = count( val = iv_xml sub = `<NODETYPE>GR</NODETYPE>` ).
    rs_signal-code_nodes = count( val = iv_xml sub = `<NODETYPE>CO</NODETYPE>` ).
    rs_signal-text_nodes = count( val = iv_xml sub = `<NODETYPE>TI</NODETYPE>` ).
    rs_signal-tables     = count( val = iv_xml regex = `<INAME>%(TABLE|TEMPLATE|LOOP)` ).
    rs_signal-conditions = count( val = iv_xml regex = `<COND>\s*<item>` ).
    rs_signal-params     = count( val = iv_xml sub = `<IOTYPE>` ).

    FIND ALL OCCURRENCES OF REGEX `<SPRAS>([A-Z0-9])</SPRAS>` IN iv_xml RESULTS DATA(lt_matches).
    LOOP AT lt_matches INTO DATA(ls_match).
      LOOP AT ls_match-submatches INTO DATA(ls_sub).
        APPEND substring( val = iv_xml off = ls_sub-offset len = ls_sub-length ) TO lt_langs.
      ENDLOOP.
    ENDLOOP.
    SORT lt_langs.
    DELETE ADJACENT DUPLICATES FROM lt_langs.
    rs_signal-languages = lines( lt_langs ).

    " Same thresholds as complexitySignal.js levelFor().
    DATA(lv_score) = band( iv_value = rs_signal-windows    iv_low = 3  iv_high = 6 )
                   + band( iv_value = rs_signal-tables     iv_low = 1  iv_high = 3 )
                   + band( iv_value = rs_signal-conditions iv_low = 3  iv_high = 8 )
                   + band( iv_value = rs_signal-languages  iv_low = 2  iv_high = 4 )
                   + band( iv_value = rs_signal-code_nodes iv_low = 1  iv_high = 4 )
                   + band( iv_value = rs_signal-graphics   iv_low = 1  iv_high = 3 )
                   + band( iv_value = rs_signal-params     iv_low = 10 iv_high = 20 ).
    rs_signal-level = COND #( WHEN lv_score >= 6 THEN `high`
                              WHEN lv_score >= 2 THEN `medium`
                              ELSE `low` ).
    rs_signal-headline = |{ rs_signal-windows } window(s), { rs_signal-tables } table/loop section(s), | &&
                         |{ rs_signal-conditions } condition(s), { nmax( val1 = rs_signal-languages val2 = 1 ) } language(s), | &&
                         |{ rs_signal-code_nodes } embedded code node(s), { rs_signal-params } interface parameter(s).|.
  ENDMETHOD.

ENDCLASS.
