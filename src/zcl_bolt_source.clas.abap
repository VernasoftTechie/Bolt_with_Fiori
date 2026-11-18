"! <p class="shorttext synchronized">Bolt with Fiori - Smart Form source (this system or DEV/QA/PRD)</p>
"! Reads the Smart Form list and one form's legacy files from the source
"! system chosen in the app. A system marked "Read from this system" is read
"! directly; any other is read over OData through its SM59 destination - the
"! same Bolt service (entities SourceForm / SourceFile) runs there too, so the
"! extraction always happens on the system that actually holds the form.
CLASS zcl_bolt_source DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_form,
        form_name      TYPE string,
        description    TYPE string,
        dev_package    TYPE string,
        created_by     TYPE string,
        created_on     TYPE string,
        changed_by     TYPE string,
        changed_on     TYPE string,
        driver_program TYPE string,
        output_types   TYPE string,
      END OF ty_form,
      ty_t_form TYPE SORTED TABLE OF ty_form WITH UNIQUE KEY form_name.

    TYPES:
      BEGIN OF ty_extract,
        files    TYPE zcl_bolt_legacy_grab=>ty_t_file,
        warnings TYPE string_table,
      END OF ty_extract.

    CONSTANTS gc_global TYPE string VALUE `*GLOBAL*`.

    CLASS-METHODS list_forms
      IMPORTING is_system       TYPE zbolt_system
                iv_prefixes     TYPE string
      RETURNING VALUE(rt_forms) TYPE ty_t_form
      RAISING   zcx_bolt.

    "! Legacy files of one form; iv_form_name = gc_global for the style/logo inventories.
    CLASS-METHODS get_files
      IMPORTING is_system         TYPE zbolt_system
                iv_form_name      TYPE string
                iv_prefixes       TYPE string
                iv_count_volume   TYPE abap_bool
      RETURNING VALUE(rs_extract) TYPE ty_extract
      RAISING   zcx_bolt.

    CLASS-METHODS test_system
      IMPORTING is_system     TYPE zbolt_system
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_bolt.

    "! Smart Forms of THIS system (TADIR SSFO + admin texts + NACE driver).
    CLASS-METHODS list_forms_local
      IMPORTING iv_prefixes     TYPE string
      RETURNING VALUE(rt_forms) TYPE ty_t_form.

    "! Legacy grab + XML export of one form on THIS system.
    CLASS-METHODS get_files_local
      IMPORTING iv_form_name      TYPE string
                iv_prefixes       TYPE string
                iv_count_volume   TYPE abap_bool
      RETURNING VALUE(rs_extract) TYPE ty_extract.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS split_prefixes
      IMPORTING iv_prefixes TYPE string
      EXPORTING ev_prefix1  TYPE string
                ev_prefix2  TYPE string.

    CLASS-METHODS remote_get
      IMPORTING is_system      TYPE zbolt_system
                iv_query       TYPE string
      RETURNING VALUE(rv_body) TYPE string
      RAISING   zcx_bolt.

    CLASS-METHODS odata_filter
      IMPORTING iv_filter      TYPE string
      RETURNING VALUE(rv_part) TYPE string.
ENDCLASS.



CLASS zcl_bolt_source IMPLEMENTATION.

  METHOD split_prefixes.
    SPLIT iv_prefixes AT ',' INTO ev_prefix1 ev_prefix2.
    ev_prefix1 = to_upper( condense( ev_prefix1 ) ).
    ev_prefix2 = to_upper( condense( ev_prefix2 ) ).
    IF ev_prefix1 IS INITIAL.
      ev_prefix1 = `Z`.
    ENDIF.
  ENDMETHOD.


  METHOD odata_filter.
    rv_part = `$filter=` && cl_http_utility=>escape_url( unescaped = iv_filter ).
  ENDMETHOD.


  METHOD remote_get.
    IF is_system-destination IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt(
        iv_text = |System { is_system-system_id } has no SM59 destination - set one, or mark it "Read from this system".| ).
    ENDIF.
    DATA(lv_path) = condense( CONV string( is_system-service_path ) ).
    IF lv_path IS INITIAL.
      lv_path = zcl_bolt_config=>gc_default_path.
    ENDIF.
    IF substring( val = lv_path off = strlen( lv_path ) - 1 len = 1 ) <> `/`.
      lv_path = lv_path && `/`.
    ENDIF.
    DATA(lv_uri) = lv_path && iv_query.
    IF is_system-sap_client IS NOT INITIAL.
      lv_uri = |{ lv_uri }&sap-client={ is_system-sap_client }|.
    ENDIF.

    DATA(ls_resp) = zcl_bolt_http=>call(
      iv_destination = is_system-destination
      iv_method      = `GET`
      iv_uri         = lv_uri
      it_headers     = VALUE #( ( name = `Accept` value = `application/json` ) )
      iv_timeout     = 600 ).
    IF ls_resp-code <> 200.
      DATA(lv_hint) = SWITCH string( ls_resp-code
        WHEN 401 THEN ` Logon failed - check the user/password in the SM59 destination.`
        WHEN 403 THEN ` The destination user is not authorized for the Bolt service on that system.`
        WHEN 404 THEN ` The Bolt service is not published on that system (or the service path is wrong).`
        ELSE `` ).
      RAISE EXCEPTION NEW zcx_bolt(
        iv_text = |System { is_system-system_id } answered HTTP { ls_resp-code } { ls_resp-reason }.{ lv_hint }| ).
    ENDIF.
    rv_body = ls_resp-body.
  ENDMETHOD.


  METHOD list_forms.
    TYPES:
      BEGIN OF ty_r_form,
        form_name      TYPE string,
        description    TYPE string,
        dev_package    TYPE string,
        created_by     TYPE string,
        created_on     TYPE string,
        changed_by     TYPE string,
        changed_on     TYPE string,
        driver_program TYPE string,
        output_types   TYPE string,
      END OF ty_r_form,
      ty_t_r_form TYPE STANDARD TABLE OF ty_r_form WITH EMPTY KEY,
      BEGIN OF ty_r_page,
        value TYPE ty_t_r_form,
      END OF ty_r_page.
    DATA ls_page TYPE ty_r_page.
    DATA lt_all  TYPE STANDARD TABLE OF ty_form WITH EMPTY KEY.

    IF is_system-is_local = abap_true.
      rt_forms = list_forms_local( iv_prefixes ).
      RETURN.
    ENDIF.

    DATA(lv_skip) = 0.
    DO 100 TIMES.
      CLEAR ls_page.
      DATA(lv_body) = remote_get(
        is_system = is_system
        iv_query  = |SourceForm?{ odata_filter( |PREFIXES eq '{ iv_prefixes }'| ) }&$orderby=FORM_NAME&$top=1000&$skip={ lv_skip }| ).
      /ui2/cl_json=>deserialize( EXPORTING json        = lv_body
                                           pretty_name = /ui2/cl_json=>pretty_mode-low_case
                                 CHANGING  data        = ls_page ).
      LOOP AT ls_page-value INTO DATA(ls_row).
        APPEND CORRESPONDING ty_form( ls_row ) TO lt_all.
      ENDLOOP.
      IF lines( ls_page-value ) < 1000.
        EXIT.
      ENDIF.
      lv_skip += 1000.
    ENDDO.
    SORT lt_all BY form_name.
    DELETE ADJACENT DUPLICATES FROM lt_all COMPARING form_name.
    rt_forms = lt_all.
  ENDMETHOD.


  METHOD list_forms_local.
    TYPES:
      BEGIN OF ty_adm,
        formname TYPE tdsfname,
        lastuser TYPE syuname,
        lastdate TYPE d,
      END OF ty_adm,
      BEGIN OF ty_txt,
        formname TYPE tdsfname,
        caption  TYPE c LENGTH 80,
      END OF ty_txt.
    DATA lt_adm   TYPE STANDARD TABLE OF ty_adm WITH EMPTY KEY.
    DATA lt_txt   TYPE STANDARD TABLE OF ty_txt WITH EMPTY KEY.
    DATA lt_forms TYPE STANDARD TABLE OF ty_form WITH EMPTY KEY.
    DATA lv_tab   TYPE string.

    split_prefixes( EXPORTING iv_prefixes = iv_prefixes
                    IMPORTING ev_prefix1  = DATA(lv_p1)
                              ev_prefix2  = DATA(lv_p2) ).
    DATA(lv_pattern1) = lv_p1 && '%'.
    DATA(lv_pattern2) = COND string( WHEN lv_p2 IS INITIAL THEN lv_pattern1 ELSE lv_p2 && '%' ).

    " Current, not deleted Smart Forms (TADIR object type SSFO) - proven by the grab.
    SELECT obj_name, devclass, author, created_on FROM tadir
      WHERE pgmid = 'R3TR' AND object = 'SSFO' AND delflag = @space
        AND ( obj_name LIKE @lv_pattern1 OR obj_name LIKE @lv_pattern2 )
      ORDER BY obj_name
      INTO TABLE @DATA(lt_tadir).

    " Last change and description from the Smart Form admin tables (the same
    " fields the XML export's HEADER carries). Read dynamically and guarded: a
    " different layout on some release leaves those columns blank, nothing more.
    DATA lv_fields TYPE string.
    DATA lv_where  TYPE string.
    TRY.
        lv_tab    = `STXFADM`.
        lv_fields = `FORMNAME, LASTUSER, LASTDATE`.
        SELECT (lv_fields) FROM (lv_tab) INTO TABLE @lt_adm.
      CATCH cx_root ##CATCH_ALL.
        CLEAR lt_adm.
    ENDTRY.
    SORT lt_adm BY formname.
    DELETE ADJACENT DUPLICATES FROM lt_adm COMPARING formname.
    TRY.
        lv_tab    = `STXFADMT`.
        lv_fields = `FORMNAME, CAPTION`.
        lv_where  = |LANGU = '{ sy-langu }'|.
        SELECT (lv_fields) FROM (lv_tab) WHERE (lv_where) INTO TABLE @lt_txt.
      CATCH cx_root ##CATCH_ALL.
        CLEAR lt_txt.
    ENDTRY.
    SORT lt_txt BY formname.
    DELETE ADJACENT DUPLICATES FROM lt_txt COMPARING formname.

    " Driver program and output types from NACE (TNAPR, matched on SFORM).
    TYPES:
      BEGIN OF ty_nace,
        formname TYPE string,
        pgnam    TYPE string,
        keys     TYPE string,
      END OF ty_nace.
    DATA lt_nace TYPE SORTED TABLE OF ty_nace WITH UNIQUE KEY formname.
    TRY.
        SELECT * FROM tnapr INTO TABLE @DATA(lt_tnapr) UP TO 50000 ROWS.
      CATCH cx_root ##CATCH_ALL.
        CLEAR lt_tnapr.
    ENDTRY.
    LOOP AT lt_tnapr INTO DATA(ls_tnapr).
      ASSIGN COMPONENT 'SFORM' OF STRUCTURE ls_tnapr TO FIELD-SYMBOL(<lfv_sform>).
      IF sy-subrc <> 0 OR <lfv_sform> IS INITIAL.
        CONTINUE.
      ENDIF.
      ASSIGN COMPONENT 'KAPPL' OF STRUCTURE ls_tnapr TO FIELD-SYMBOL(<lfv_kappl>).
      ASSIGN COMPONENT 'KSCHL' OF STRUCTURE ls_tnapr TO FIELD-SYMBOL(<lfv_kschl>).
      DATA(lv_key) = COND string( WHEN <lfv_kappl> IS ASSIGNED AND <lfv_kschl> IS ASSIGNED
                                  THEN |{ <lfv_kappl> }/{ <lfv_kschl> }| ).
      DATA(lv_form) = to_upper( |{ <lfv_sform> }| ).
      ASSIGN lt_nace[ formname = lv_form ] TO FIELD-SYMBOL(<lfs_nace>).
      IF sy-subrc = 0.
        IF lv_key IS NOT INITIAL AND find( val = <lfs_nace>-keys sub = lv_key ) < 0.
          <lfs_nace>-keys = |{ <lfs_nace>-keys }, { lv_key }|.
        ENDIF.
      ELSE.
        lt_nace = VALUE #( BASE lt_nace ( formname = lv_form pgnam = condense( CONV string( ls_tnapr-pgnam ) ) keys = lv_key ) ).
      ENDIF.
      UNASSIGN: <lfv_kappl>, <lfv_kschl>.
    ENDLOOP.

    LOOP AT lt_tadir INTO DATA(ls_tadir).
      DATA(ls_form) = VALUE ty_form( form_name   = condense( CONV string( ls_tadir-obj_name ) )
                                     dev_package = condense( CONV string( ls_tadir-devclass ) )
                                     created_by  = condense( CONV string( ls_tadir-author ) )
                                     created_on  = |{ ls_tadir-created_on DATE = RAW }| ).
      READ TABLE lt_adm INTO DATA(ls_adm) WITH KEY formname = ls_tadir-obj_name BINARY SEARCH.
      IF sy-subrc = 0.
        ls_form-changed_by = condense( CONV string( ls_adm-lastuser ) ).
        ls_form-changed_on = |{ ls_adm-lastdate DATE = RAW }|.
      ENDIF.
      READ TABLE lt_txt INTO DATA(ls_txt) WITH KEY formname = ls_tadir-obj_name BINARY SEARCH.
      IF sy-subrc = 0.
        ls_form-description = condense( CONV string( ls_txt-caption ) ).
      ENDIF.
      READ TABLE lt_nace INTO DATA(ls_nace) WITH TABLE KEY formname = ls_form-form_name.
      IF sy-subrc = 0.
        ls_form-driver_program = ls_nace-pgnam.
        ls_form-output_types   = ls_nace-keys.
      ENDIF.
      IF ls_form-created_on = `00000000`.
        CLEAR ls_form-created_on.
      ENDIF.
      IF ls_form-changed_on = `00000000`.
        CLEAR ls_form-changed_on.
      ENDIF.
      APPEND ls_form TO lt_forms.
    ENDLOOP.

    SORT lt_forms BY form_name.
    DELETE ADJACENT DUPLICATES FROM lt_forms COMPARING form_name.
    rt_forms = lt_forms.
  ENDMETHOD.


  METHOD get_files.
    TYPES:
      BEGIN OF ty_r_file,
        form_name  TYPE string,
        file_name  TYPE string,
        kind       TYPE string,
        size_bytes TYPE i,
        content    TYPE string,
        message    TYPE string,
      END OF ty_r_file,
      ty_t_r_file TYPE STANDARD TABLE OF ty_r_file WITH EMPTY KEY,
      BEGIN OF ty_r_page,
        value TYPE ty_t_r_file,
      END OF ty_r_page.
    DATA ls_page TYPE ty_r_page.

    IF is_system-is_local = abap_true.
      rs_extract = get_files_local( iv_form_name    = iv_form_name
                                    iv_prefixes     = iv_prefixes
                                    iv_count_volume = iv_count_volume ).
      RETURN.
    ENDIF.

    DATA(lv_filter) = |FORM_NAME eq '{ iv_form_name }' and PREFIXES eq '{ iv_prefixes }'| &&
                      | and COUNT_VOLUME eq '{ COND string( WHEN iv_count_volume = abap_true THEN `X` ) }'|.
    DATA(lv_body) = remote_get( is_system = is_system
                                iv_query  = |SourceFile?{ odata_filter( lv_filter ) }| ).
    /ui2/cl_json=>deserialize( EXPORTING json        = lv_body
                                         pretty_name = /ui2/cl_json=>pretty_mode-low_case
                               CHANGING  data        = ls_page ).
    LOOP AT ls_page-value INTO DATA(ls_row).
      IF ls_row-message IS NOT INITIAL AND rs_extract-warnings IS INITIAL.
        SPLIT ls_row-message AT cl_abap_char_utilities=>newline INTO TABLE rs_extract-warnings.
      ENDIF.
      IF ls_row-kind = `NONE`.
        CONTINUE. " placeholder row that only carries the warnings
      ENDIF.
      APPEND VALUE #( name = ls_row-file_name kind = ls_row-kind content = ls_row-content ) TO rs_extract-files.
    ENDLOOP.
    IF rs_extract-files IS INITIAL AND rs_extract-warnings IS INITIAL.
      RAISE EXCEPTION NEW zcx_bolt(
        iv_text = |System { is_system-system_id } returned no files for { iv_form_name } - does the form exist there?| ).
    ENDIF.
  ENDMETHOD.


  METHOD get_files_local.
    split_prefixes( EXPORTING iv_prefixes = iv_prefixes
                    IMPORTING ev_prefix1  = DATA(lv_p1)
                              ev_prefix2  = DATA(lv_p2) ).
    DATA(lo_grab) = NEW zcl_bolt_legacy_grab( iv_prefix1      = lv_p1
                                              iv_prefix2      = lv_p2
                                              iv_count_volume = iv_count_volume ).
    IF iv_form_name = gc_global.
      rs_extract-files = lo_grab->global_sweep( ).
      RETURN.
    ENDIF.

    DATA(lv_form) = to_upper( condense( iv_form_name ) ).
    SELECT SINGLE obj_name FROM tadir
      WHERE pgmid = 'R3TR' AND object = 'SSFO' AND obj_name = @lv_form
      INTO @DATA(lv_exists).
    IF sy-subrc <> 0.
      APPEND |Smart Form { lv_form } does not exist on system { sy-sysid } client { sy-mandt }.| TO rs_extract-warnings.
      RETURN.
    ENDIF.

    TRY.
        rs_extract-files = lo_grab->grab_form( lv_form ).
      CATCH cx_root INTO DATA(lx_grab) ##CATCH_ALL.
        APPEND |Legacy grab of { lv_form } failed: { lx_grab->get_text( ) }| TO rs_extract-warnings.
    ENDTRY.

    TRY.
        DATA(lv_xml) = zcl_bolt_form_export=>export_xml( lv_form ).
        APPEND VALUE #( name    = |{ to_lower( translate( val = lv_form from = `/` to = `_` ) ) }.xml|
                        kind    = `XML`
                        content = lv_xml ) TO rs_extract-files.
      CATCH cx_root INTO DATA(lx_xml) ##CATCH_ALL.
        APPEND |Smart Form XML export failed ({ lx_xml->get_text( ) }) - download it in SMARTFORMS | &&
               |(Utilities > Download Form) and attach it on the Migration page.| TO rs_extract-warnings.
    ENDTRY.
  ENDMETHOD.


  METHOD test_system.
    IF is_system-is_local = abap_true.
      DATA(lt_forms) = list_forms_local( `Z,Y` ).
      rv_text = |Reads this system directly ({ sy-sysid } client { sy-mandt }) - { lines( lt_forms ) } custom Smart Form(s) visible.|.
      RETURN.
    ENDIF.
    DATA(lv_body) = remote_get( is_system = is_system
                                iv_query  = `SourceForm?$top=1&$count=true` ).
    DATA lv_count TYPE string.
    FIND FIRST OCCURRENCE OF REGEX `"@odata\.count"\s*:\s*(\d+)` IN lv_body SUBMATCHES lv_count.
    rv_text = |Connected to { is_system-system_id }{ COND string( WHEN is_system-sap_client IS NOT INITIAL
                                                                   THEN | client { is_system-sap_client }| ) } | &&
              |- the Bolt service answered{ COND string( WHEN lv_count IS NOT INITIAL
                                                         THEN |, { lv_count } custom Smart Form(s) visible| ) }.|.
  ENDMETHOD.

ENDCLASS.
