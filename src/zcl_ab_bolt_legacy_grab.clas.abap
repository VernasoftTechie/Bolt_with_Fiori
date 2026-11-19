"! <p class="shorttext synchronized">Bolt with Fiori - legacy grab of one Smart Form (port)</p>
"! Port of report ZSF2AF_R_LEGACY_GRAB (VernasoftTechie/Smartform-Adobe-
"! Migration, src/) into a class that RETURNS its files instead of writing
"! them to the PC with GUI_DOWNLOAD - so it runs inside the Fiori app and in
"! background jobs. Every snapshot section, heading and line is kept word for
"! word: the engineer tools read section 2c of the .md (sfp_interface.mjs
"! --grab), so the text is a contract, not decoration.
"!
"! What changed, and only this:
"!   - output: GT_FILES (name + content) instead of GUI_DOWNLOAD to P_PATH;
"!     driver files keep their names (driver_<PROGRAM>.txt)
"!   - selection-screen parameters became constructor parameters
"!   - the slow "scan every Z*/Y* program" step (build_driver_index) runs in
"!     report ZABR_BOLT_DRIVER_INDEX and is stored in ZABT_BOLT_DRVIX; one form's
"!     grab reads that index (plus the NACE driver, always) - one click stays
"!     fast. If the index was never built, section 3 says so.
"!   - attribute/field-symbol names follow the DIL naming policy
CLASS zcl_ab_bolt_legacy_grab DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_file,
        name    TYPE string,
        kind    TYPE string,
        content TYPE string,
      END OF ty_file,
      ty_t_file TYPE STANDARD TABLE OF ty_file WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_idx,
        formname TYPE string,
        progname TYPE tadir-obj_name,
      END OF ty_idx,
      ty_t_idx TYPE STANDARD TABLE OF ty_idx WITH EMPTY KEY.

    METHODS constructor
      IMPORTING iv_prefix1      TYPE string    DEFAULT `Z`
                iv_prefix2      TYPE string    DEFAULT `Y`
                iv_count_volume TYPE abap_bool DEFAULT abap_true.

    "! Snapshot <FORM>.md plus every driver/include source it extracted.
    METHODS grab_form
      IMPORTING iv_formname     TYPE string
      RETURNING VALUE(rt_files) TYPE ty_t_file.

    "! global_smartstyles.txt and global_logos.txt (the old P_GLOB sweep).
    METHODS global_sweep
      RETURNING VALUE(rt_files) TYPE ty_t_file.

    "! The slow step: scans every custom program once, for all forms at once.
    "! Returns form/program pairs only (no files) - used by ZABR_BOLT_DRIVER_INDEX.
    METHODS build_driver_index
      IMPORTING it_forms      TYPE string_table
      RETURNING VALUE(rt_idx) TYPE ty_t_idx.

    METHODS get_log
      RETURNING VALUE(rt_log) TYPE string_table.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_driver_hit,
        progname TYPE tadir-obj_name,
      END OF ty_driver_hit,
      ty_t_driver_hit TYPE STANDARD TABLE OF ty_driver_hit WITH EMPTY KEY.

    " Per driver program: where its extracted source landed, what other
    " Z*/Y* objects it appears to reference, and which of its own
    " INCLUDEs were followed and extracted too (one level deep).
    TYPES:
      BEGIN OF ty_prog_info,
        progname      TYPE tadir-obj_name,
        source_file   TYPE string,
        deps          TYPE string_table,
        include_files TYPE string_table,
      END OF ty_prog_info,
      ty_t_prog_info TYPE STANDARD TABLE OF ty_prog_info WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_kind,
        code  TYPE c LENGTH 1,
        title TYPE string,
      END OF ty_kind,
      ty_t_kind TYPE STANDARD TABLE OF ty_kind WITH EMPTY KEY.

    DATA gv_pref1               TYPE string.
    DATA gv_pref2               TYPE string.
    DATA gv_count_volume        TYPE abap_bool.
    DATA gv_index_built         TYPE abap_bool.
    DATA gt_prog_info           TYPE ty_t_prog_info.
    DATA gt_ssf_read_form_iface TYPE string_table.
    DATA gt_files               TYPE ty_t_file.
    DATA gt_log                 TYPE string_table.

    METHODS add_file
      IMPORTING iv_name  TYPE string
                iv_kind  TYPE string
                it_lines TYPE string_table.

    METHODS indexed_drivers
      IMPORTING iv_formname   TYPE string
      RETURNING VALUE(rt_idx) TYPE ty_t_idx.

    METHODS is_custom
      IMPORTING iv_name          TYPE clike
      RETURNING VALUE(rv_custom) TYPE abap_bool.

    METHODS dump_nonempty
      IMPORTING is_row         TYPE any
                it_skip        TYPE string_table OPTIONAL
      RETURNING VALUE(rv_text) TYPE string.

    METHODS interface_custom_types
      IMPORTING iv_fm_name      TYPE char30
      RETURNING VALUE(rt_types) TYPE string_table.

    METHODS describe_type
      IMPORTING iv_type         TYPE string
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS classify_scalar
      IMPORTING iv_type        TYPE string
      RETURNING VALUE(rv_kind) TYPE string.

    METHODS capture_reference_requirements
      IMPORTING iv_fm_name      TYPE char30
                it_custom_types TYPE string_table
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS context_build_order
      IMPORTING iv_fm_name      TYPE char30
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS context_node_shapes
      IMPORTING iv_fm_name      TYPE char30
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS context_struct_fields
      IMPORTING iv_param        TYPE string
                iv_descr        TYPE REF TO cl_abap_typedescr
                iv_role         TYPE string
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS dependency_fm_interfaces
      IMPORTING it_deps         TYPE string_table
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS capture_volume
      IMPORTING iv_kappl        TYPE nast-kappl
                iv_kschl        TYPE nast-kschl
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS ensure_driver_extracted
      IMPORTING iv_progname TYPE string.

    METHODS driver_info_lines
      IMPORTING iv_progname     TYPE string
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS write_driver_source
      IMPORTING iv_progname    TYPE tadir-obj_name
                it_source      TYPE string_table
      RETURNING VALUE(rv_file) TYPE string.

    METHODS scan_dependencies
      IMPORTING it_source       TYPE string_table
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS extract_includes
      IMPORTING it_source        TYPE string_table
      CHANGING  ct_include_files TYPE string_table
                ct_deps          TYPE string_table.

    METHODS get_prog_info
      IMPORTING iv_progname    TYPE tadir-obj_name
      RETURNING VALUE(rs_info) TYPE ty_prog_info.

    METHODS process_form
      IMPORTING iv_formname TYPE string
                it_idx      TYPE ty_t_idx.

    METHODS resolve_fm_name
      IMPORTING iv_formname  TYPE string
      RETURNING VALUE(rv_fm) TYPE char30.

    METHODS dump_any
      IMPORTING iv_data         TYPE any
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS capture_interface
      IMPORTING iv_fm_name      TYPE char30
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS capture_output_determination
      IMPORTING iv_formname     TYPE string
      EXPORTING et_pgnam        TYPE string_table
                et_keys         TYPE string_table
                et_lines        TYPE string_table.

    METHODS probe_form_storage
      IMPORTING iv_formname     TYPE string
      RETURNING VALUE(rt_lines) TYPE string_table.

    METHODS write_snapshot
      IMPORTING iv_formname TYPE string
                iv_fm_name  TYPE char30
                it_drivers  TYPE ty_t_driver_hit.

    METHODS w
      IMPORTING iv TYPE string.
ENDCLASS.



CLASS zcl_ab_bolt_legacy_grab IMPLEMENTATION.

  METHOD constructor.
    gv_pref1        = to_upper( condense( iv_prefix1 ) ).
    gv_pref2        = to_upper( condense( iv_prefix2 ) ).
    gv_count_volume = iv_count_volume.
    IF gv_pref1 IS INITIAL.
      gv_pref1 = `Z`.
    ENDIF.
  ENDMETHOD.


  METHOD get_log.
    rt_log = gt_log.
  ENDMETHOD.


  METHOD w.
    APPEND iv TO gt_log.
  ENDMETHOD.


  METHOD add_file.
    IF line_exists( gt_files[ name = iv_name ] ).
      RETURN.
    ENDIF.
    " GUI_DOWNLOAD (ASC) ended every line with a line break - kept identical.
    APPEND VALUE #( name    = iv_name
                    kind    = iv_kind
                    content = concat_lines_of( table = it_lines sep = cl_abap_char_utilities=>newline )
                              && cl_abap_char_utilities=>newline ) TO gt_files.
  ENDMETHOD.


  METHOD grab_form.
    CLEAR: gt_files, gt_prog_info, gt_log.
    IF gt_ssf_read_form_iface IS INITIAL.
      gt_ssf_read_form_iface = capture_interface( 'SSF_READ_FORM' ).
    ENDIF.
    DATA(lv_form) = to_upper( condense( iv_formname ) ).
    DATA(lt_idx) = indexed_drivers( lv_form ).
    process_form( iv_formname = lv_form it_idx = lt_idx ).
    rt_files = gt_files.
  ENDMETHOD.


  METHOD indexed_drivers.
    DATA lv_form TYPE zabt_bolt_drvix-form_name.

    SELECT COUNT( * ) FROM zabt_bolt_drvix INTO @DATA(lv_count).
    gv_index_built = xsdbool( lv_count > 0 ).

    lv_form = iv_formname.
    SELECT prog_name FROM zabt_bolt_drvix
      WHERE form_name = @lv_form
      ORDER BY prog_name
      INTO TABLE @DATA(lt_progs).

    LOOP AT lt_progs INTO DATA(ls_prog).
      ensure_driver_extracted( CONV string( ls_prog-prog_name ) ).
      APPEND VALUE #( formname = iv_formname progname = ls_prog-prog_name ) TO rt_idx.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_driver_index.
    DATA lt_source        TYPE string_table.
    DATA lt_matched_forms TYPE string_table.
    DATA lt_call_idx      TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    DATA lv_found         TYPE abap_bool.
    DATA lv_from          TYPE i.
    DATA lv_to            TYPE i.
    DATA lv_window        TYPE string.

    DATA(lv_pattern)  = gv_pref1 && '%'.
    DATA(lv_pattern2) = COND string( WHEN gv_pref2 IS INITIAL THEN lv_pattern ELSE gv_pref2 && '%' ).
    SELECT obj_name FROM tadir
      WHERE pgmid = 'R3TR' AND object = 'PROG'
        AND ( obj_name LIKE @lv_pattern OR obj_name LIKE @lv_pattern2 )
      ORDER BY obj_name
      INTO TABLE @DATA(lt_prog).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    w( |Scanning { lines( lt_prog ) } program(s) once for driver candidates (this is the slow step)...| ).

    LOOP AT lt_prog INTO DATA(ls_prog).
      CLEAR lt_source.
      READ REPORT ls_prog-obj_name INTO lt_source.
      IF sy-subrc <> 0 OR lt_source IS INITIAL.
        CONTINUE.
      ENDIF.

      " Every line where SSF_FUNCTION_MODULE_NAME is actually called - a
      " program can call it more than once, for more than one form.
      CLEAR lt_call_idx.
      LOOP AT lt_source INTO DATA(lv_line).
        IF lv_line CS 'SSF_FUNCTION_MODULE_NAME'.
          APPEND sy-tabix TO lt_call_idx.
        ENDIF.
      ENDLOOP.
      IF lt_call_idx IS INITIAL.
        CONTINUE.
      ENDIF.

      " Form name within +/-20 lines of a real call site (ZSD_ATC false-positive
      " fix, BUILD_ISSUES_LOG.md) - still only a CANDIDATE; the snapshot
      " cross-checks it against NACE/TNAPR's PGNAM.
      CLEAR lt_matched_forms.
      LOOP AT it_forms INTO DATA(lv_form).
        lv_found = abap_false.
        LOOP AT lt_call_idx INTO DATA(lv_hit_idx).
          lv_from = lv_hit_idx - 20.
          IF lv_from < 1.
            lv_from = 1.
          ENDIF.
          lv_to = lv_hit_idx + 20.
          CLEAR lv_window.
          LOOP AT lt_source INTO DATA(lv_wline) FROM lv_from TO lv_to.
            lv_window = lv_window && lv_wline && | |.
          ENDLOOP.
          IF lv_window CS lv_form.
            lv_found = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
        IF lv_found = abap_true.
          APPEND lv_form TO lt_matched_forms.
        ENDIF.
      ENDLOOP.

      LOOP AT lt_matched_forms INTO lv_form.
        APPEND VALUE #( formname = lv_form progname = ls_prog-obj_name ) TO rt_idx.
      ENDLOOP.
    ENDLOOP.
    SORT rt_idx BY formname progname.
    DELETE ADJACENT DUPLICATES FROM rt_idx COMPARING formname progname.
  ENDMETHOD.


  METHOD write_driver_source.
    DATA(lv_prog) = condense( CONV string( iv_progname ) ).
    rv_file = |driver_{ translate( val = lv_prog from = `/` to = `_` ) }.txt|.
    add_file( iv_name = rv_file iv_kind = `DRIVER` it_lines = it_source ).
  ENDMETHOD.


  METHOD scan_dependencies.
    LOOP AT it_source INTO DATA(lv_line).
      DATA(lv_trim) = |{ lv_line }|.
      IF lv_trim IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_is_dep) = abap_false.
      IF    lv_trim CS `CALL FUNCTION 'Z` OR lv_trim CS `CALL FUNCTION 'Y`
         OR lv_trim CS `CALL METHOD ZCL_` OR lv_trim CS `CALL METHOD YCL_`
         OR lv_trim CS `NEW ZCL_`         OR lv_trim CS `NEW YCL_`
         OR lv_trim CS `TYPE ZCL_`        OR lv_trim CS `TYPE YCL_`
         OR lv_trim CS `INCLUDE Z`        OR lv_trim CS `INCLUDE Y`.
        lv_is_dep = abap_true.
      ENDIF.
      IF lv_trim CS `PERFORM`.
        IF lv_trim CS `(Z` OR lv_trim CS `(Y`.
          lv_is_dep = abap_true.
        ENDIF.
      ENDIF.

      IF lv_is_dep = abap_true.
        APPEND lv_trim TO rt_lines.
      ENDIF.
    ENDLOOP.

    SORT rt_lines.
    DELETE ADJACENT DUPLICATES FROM rt_lines.
  ENDMETHOD.


  METHOD extract_includes.
    DATA lv_inclname   TYPE tadir-obj_name.
    DATA lt_inc_source TYPE string_table.

    LOOP AT it_source INTO DATA(lv_line).
      DATA(lv_work) = lv_line.
      CONDENSE lv_work.
      IF lv_work IS INITIAL.
        CONTINUE.
      ENDIF.
      IF NOT to_upper( lv_work ) CP 'INCLUDE *'.
        CONTINUE.
      ENDIF.

      SPLIT lv_work AT space INTO TABLE DATA(lt_words).
      DELETE lt_words WHERE table_line IS INITIAL.
      IF lines( lt_words ) < 2.
        CONTINUE.
      ENDIF.

      " Fixed CHAR type, not STRING: offset/length below needs C/N/D/T and
      " write_driver_source's IV_PROGNAME is TYPE tadir-obj_name.
      lv_inclname = to_upper( lt_words[ 2 ] ).
      DATA(lv_len) = strlen( lv_inclname ) - 1.
      IF lv_len > 0 AND lv_inclname+lv_len(1) = '.'.
        lv_inclname = lv_inclname(lv_len).
      ENDIF.

      IF is_custom( lv_inclname ) = abap_false.
        " only follow custom includes, not standard SAP includes
        CONTINUE.
      ENDIF.

      CLEAR lt_inc_source.
      READ REPORT lv_inclname INTO lt_inc_source.
      IF sy-subrc <> 0 OR lt_inc_source IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lv_inc_file) = write_driver_source( iv_progname = lv_inclname it_source = lt_inc_source ).
      IF lv_inc_file IS NOT INITIAL.
        APPEND |{ lv_inclname } -> { lv_inc_file }| TO ct_include_files.
      ENDIF.

      APPEND LINES OF scan_dependencies( lt_inc_source ) TO ct_deps.
    ENDLOOP.

    SORT ct_include_files.
    DELETE ADJACENT DUPLICATES FROM ct_include_files.
    SORT ct_deps.
    DELETE ADJACENT DUPLICATES FROM ct_deps.
  ENDMETHOD.


  METHOD get_prog_info.
    READ TABLE gt_prog_info INTO rs_info WITH KEY progname = iv_progname.
    IF sy-subrc <> 0.
      CLEAR rs_info.
    ENDIF.
  ENDMETHOD.


  METHOD resolve_fm_name.
    " SSF_FUNCTION_MODULE_NAME's FORMNAME is a fixed-length classic type, not
    " STRING - passing a STRING directly dumps CALL_FUNCTION_CONFLICT_TYPE.
    DATA lv_formname TYPE tdsfname.
    lv_formname = iv_formname.

    CALL FUNCTION 'SSF_FUNCTION_MODULE_NAME'
      EXPORTING
        formname = lv_formname
      IMPORTING
        fm_name  = rv_fm
      EXCEPTIONS
        OTHERS   = 1.
    IF sy-subrc <> 0.
      CLEAR rv_fm.
    ENDIF.
  ENDMETHOD.


  METHOD dump_any.
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( iv_data ).
    IF lo_type->kind = cl_abap_typedescr=>kind_struct.
      DATA(lo_struct) = CAST cl_abap_structdescr( lo_type ).
      LOOP AT lo_struct->components INTO DATA(ls_comp).
        ASSIGN COMPONENT ls_comp-name OF STRUCTURE iv_data TO FIELD-SYMBOL(<lfv_value>).
        IF sy-subrc = 0.
          APPEND |{ ls_comp-name } = { <lfv_value> }| TO rt_lines.
        ENDIF.
      ENDLOOP.
    ELSE.
      APPEND |{ iv_data }| TO rt_lines.
    ENDIF.
  ENDMETHOD.


  METHOD capture_interface.
    IF iv_fm_name IS INITIAL.
      APPEND `(no generated function module - see section 1)` TO rt_lines.
      RETURN.
    ENDIF.

    " FUPARAREF, SELECT * (no guessed column list) - proven technique (A18).
    SELECT * FROM fupararef
      WHERE funcname = @iv_fm_name AND r3state = 'A'
      INTO TABLE @DATA(lt_params).
    IF sy-subrc <> 0 OR lt_params IS INITIAL.
      APPEND |(no FUPARAREF rows for { iv_fm_name } - confirm manually via SE37)| TO rt_lines.
      RETURN.
    ENDIF.

    DATA(lt_kind) = VALUE ty_t_kind(
      ( code = 'I' title = `IMPORTING:` )
      ( code = 'E' title = `EXPORTING:` )
      ( code = 'T' title = `TABLES:` )
      ( code = 'C' title = `CHANGING:` )
      ( code = 'X' title = `EXCEPTIONS:` ) ).
    DATA(lt_skip) = VALUE string_table(
      ( `FUNCNAME` ) ( `R3STATE` ) ( `PARAMETER` ) ( `PARAMTYPE` ) ).

    LOOP AT lt_kind INTO DATA(ls_kind).
      APPEND ls_kind-title TO rt_lines.
      LOOP AT lt_params INTO DATA(ls_p) WHERE paramtype = ls_kind-code.
        DATA(lv_detail) = dump_nonempty( is_row = ls_p it_skip = lt_skip ).
        IF lv_detail IS INITIAL.
          APPEND |- { ls_p-parameter }| TO rt_lines.
        ELSE.
          APPEND |- { ls_p-parameter } ({ lv_detail })| TO rt_lines.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_custom.
    rv_custom = abap_false.
    IF iv_name IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_up) = to_upper( |{ iv_name }| ).
    IF gv_pref1 IS NOT INITIAL AND lv_up CP |{ gv_pref1 }*|.
      rv_custom = abap_true.
    ELSEIF gv_pref2 IS NOT INITIAL AND lv_up CP |{ gv_pref2 }*|.
      rv_custom = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD dump_nonempty.
    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( is_row ).
    IF lo_type->kind <> cl_abap_typedescr=>kind_struct.
      RETURN.
    ENDIF.
    DATA(lo_struct) = CAST cl_abap_structdescr( lo_type ).
    LOOP AT lo_struct->components INTO DATA(ls_comp).
      READ TABLE it_skip WITH KEY table_line = ls_comp-name TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE is_row TO FIELD-SYMBOL(<lfv_value>).
      IF sy-subrc <> 0 OR <lfv_value> IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(lo_comp_type) = cl_abap_typedescr=>describe_by_data( <lfv_value> ).
      IF lo_comp_type->kind <> cl_abap_typedescr=>kind_elem.
        CONTINUE.
      ENDIF.
      DATA(lv_val) = |{ <lfv_value> }|.
      CONDENSE lv_val.
      IF rv_text IS INITIAL.
        rv_text = |{ ls_comp-name }={ lv_val }|.
      ELSE.
        rv_text = |{ rv_text }, { ls_comp-name }={ lv_val }|.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD interface_custom_types.
    IF iv_fm_name IS INITIAL.
      RETURN.
    ENDIF.
    SELECT * FROM fupararef
      WHERE funcname = @iv_fm_name AND r3state = 'A'
      INTO TABLE @DATA(lt_params).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_params INTO DATA(ls_p).
      DATA(lo_struct) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_data( ls_p ) ).
      LOOP AT lo_struct->components INTO DATA(ls_comp).
        IF ls_comp-name = 'FUNCNAME' OR ls_comp-name = 'PARAMETER'.
          CONTINUE.
        ENDIF.
        ASSIGN COMPONENT ls_comp-name OF STRUCTURE ls_p TO FIELD-SYMBOL(<lfv_value>).
        IF sy-subrc <> 0 OR <lfv_value> IS INITIAL.
          CONTINUE.
        ENDIF.
        DATA(lo_comp_type) = cl_abap_typedescr=>describe_by_data( <lfv_value> ).
        IF lo_comp_type->kind <> cl_abap_typedescr=>kind_elem.
          CONTINUE.
        ENDIF.
        DATA(lv_val) = to_upper( |{ <lfv_value> }| ).
        CONDENSE lv_val.
        " > 2 characters: single-letter flags ('X', 'Y') are not type names.
        IF strlen( lv_val ) > 2 AND is_custom( lv_val ) = abap_true.
          APPEND lv_val TO rt_types.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    SORT rt_types.
    DELETE ADJACENT DUPLICATES FROM rt_types.
  ENDMETHOD.


  METHOD describe_type.
    DATA lo_descr  TYPE REF TO cl_abap_typedescr.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    DATA lt_fields TYPE ddfields.

    " Classic EXCEPTIONS handling: TYPE_NOT_FOUND is not class-based (F12).
    CALL METHOD cl_abap_typedescr=>describe_by_name
      EXPORTING
        p_name         = iv_type
      RECEIVING
        p_descr_ref    = lo_descr
      EXCEPTIONS
        type_not_found = 1
        OTHERS         = 2.
    IF sy-subrc <> 0 OR lo_descr IS NOT BOUND.
      APPEND |`{ iv_type }`: not found as a DDIC type on this system - confirm manually in SE11.| TO rt_lines.
      RETURN.
    ENDIF.

    IF lo_descr->kind = cl_abap_typedescr=>kind_table.
      DATA(lo_line) = CAST cl_abap_tabledescr( lo_descr )->get_table_line_type( ).
      APPEND |`{ iv_type }` is a table type - line type:| TO rt_lines.
      IF lo_line->kind = cl_abap_typedescr=>kind_struct.
        lo_struct = CAST cl_abap_structdescr( lo_line ).
      ENDIF.
    ELSEIF lo_descr->kind = cl_abap_typedescr=>kind_struct.
      lo_struct = CAST cl_abap_structdescr( lo_descr ).
    ELSE.
      APPEND |`{ iv_type }`: elementary type ({ lo_descr->type_kind }, length { lo_descr->length }).| TO rt_lines.
      RETURN.
    ENDIF.

    IF lo_struct IS NOT BOUND.
      APPEND |`{ iv_type }`: not a structure - confirm manually in SE11.| TO rt_lines.
      RETURN.
    ENDIF.

    CALL METHOD lo_struct->get_ddic_field_list
      RECEIVING
        p_field_list = lt_fields
      EXCEPTIONS
        not_found    = 1
        no_ddic_type = 2
        OTHERS       = 3.
    IF sy-subrc = 0 AND lt_fields IS NOT INITIAL.
      APPEND |`{ iv_type }` - { lines( lt_fields ) } field(s):| TO rt_lines.
      LOOP AT lt_fields INTO DATA(ls_f).
        APPEND |- { ls_f-fieldname } (element { ls_f-rollname }, type { ls_f-datatype }, length { ls_f-leng }, decimals { ls_f-decimals })| TO rt_lines.
      ENDLOOP.
    ELSE.
      " Not a DDIC-backed structure: fall back to the technical components.
      APPEND |`{ iv_type }` - technical components (no DDIC field list available):| TO rt_lines.
      LOOP AT lo_struct->components INTO DATA(ls_c).
        APPEND |- { ls_c-name } (type kind { ls_c-type_kind }, length { ls_c-length }, decimals { ls_c-decimals })| TO rt_lines.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.


  METHOD classify_scalar.
    DATA lo_descr TYPE REF TO cl_abap_typedescr.
    DATA lo_elem  TYPE REF TO cl_abap_elemdescr.
    DATA ls_dfies TYPE dfies.

    CALL METHOD cl_abap_typedescr=>describe_by_name
      EXPORTING
        p_name         = iv_type
      RECEIVING
        p_descr_ref    = lo_descr
      EXCEPTIONS
        type_not_found = 1
        OTHERS         = 2.
    IF sy-subrc <> 0 OR lo_descr IS NOT BOUND OR lo_descr->kind <> cl_abap_typedescr=>kind_elem.
      RETURN.
    ENDIF.
    TRY.
        lo_elem = CAST cl_abap_elemdescr( lo_descr ).
      CATCH cx_root ##CATCH_ALL.
        RETURN.
    ENDTRY.
    CALL METHOD lo_elem->get_ddic_field
      EXPORTING
        p_langu    = sy-langu
      RECEIVING
        p_flddescr = ls_dfies
      EXCEPTIONS
        not_found  = 1
        OTHERS     = 2.
    IF sy-subrc = 0.
      rv_kind = ls_dfies-datatype.
    ENDIF.
  ENDMETHOD.


  METHOD capture_reference_requirements.
    TYPES:
      BEGIN OF ty_hit,
        owner_type TYPE string,
        fieldname  TYPE string,
        datatype   TYPE string,
        reftable   TYPE string,
        reffield   TYPE string,
      END OF ty_hit,
      ty_t_hit TYPE STANDARD TABLE OF ty_hit WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_scalar,
        name TYPE string,
        kind TYPE string,
      END OF ty_scalar,
      ty_t_scalar TYPE STANDARD TABLE OF ty_scalar WITH EMPTY KEY.

    DATA lt_hits       TYPE ty_t_hit.
    DATA lt_scalars    TYPE ty_t_scalar.
    DATA lo_descr      TYPE REF TO cl_abap_typedescr.
    DATA lo_struct     TYPE REF TO cl_abap_structdescr.
    DATA lt_fields     TYPE ddfields.
    DATA lv_resolution TYPE string.
    DATA lv_typename   TYPE string.

    LOOP AT it_custom_types INTO DATA(lv_type).
      CLEAR: lo_descr, lo_struct, lt_fields.
      CALL METHOD cl_abap_typedescr=>describe_by_name
        EXPORTING
          p_name         = lv_type
        RECEIVING
          p_descr_ref    = lo_descr
        EXCEPTIONS
          type_not_found = 1
          OTHERS         = 2.
      IF sy-subrc <> 0 OR lo_descr IS NOT BOUND.
        CONTINUE.
      ENDIF.
      IF lo_descr->kind = cl_abap_typedescr=>kind_table.
        DATA(lo_line) = CAST cl_abap_tabledescr( lo_descr )->get_table_line_type( ).
        IF lo_line->kind = cl_abap_typedescr=>kind_struct.
          lo_struct = CAST cl_abap_structdescr( lo_line ).
        ENDIF.
      ELSEIF lo_descr->kind = cl_abap_typedescr=>kind_struct.
        lo_struct = CAST cl_abap_structdescr( lo_descr ).
      ENDIF.
      IF lo_struct IS NOT BOUND.
        CONTINUE.
      ENDIF.

      CALL METHOD lo_struct->get_ddic_field_list
        RECEIVING
          p_field_list = lt_fields
        EXCEPTIONS
          not_found    = 1
          no_ddic_type = 2
          OTHERS       = 3.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      LOOP AT lt_fields INTO DATA(ls_f) WHERE datatype = 'CURR' OR datatype = 'QUAN'.
        APPEND VALUE #( owner_type = lv_type fieldname = ls_f-fieldname datatype = ls_f-datatype
                        reftable   = ls_f-reftable reffield = ls_f-reffield ) TO lt_hits.
      ENDLOOP.
    ENDLOOP.

    IF lt_hits IS INITIAL.
      APPEND `No CURR/QUAN fields found in this interface's custom table/structure types.` TO rt_lines.
      RETURN.
    ENDIF.

    " This form's own import parameters as candidate top-level UNIT scalars,
    " classified by DDIC domain where possible (CUKY / UNIT).
    SELECT parameter, paramtype FROM fupararef
      WHERE funcname = @iv_fm_name AND r3state = 'A' AND paramtype = 'I'
      INTO TABLE @DATA(lt_params).
    LOOP AT lt_params INTO DATA(ls_p).
      DATA(lv_tname) = dump_nonempty( is_row = ls_p it_skip = VALUE string_table( ( `FUNCNAME` ) ( `PARAMETER` ) ( `PARAMTYPE` ) ) ).
      " TYPENAME is one of the dumped fields; pull it out rather than re-querying.
      CLEAR lv_typename.
      FIND REGEX 'TYPENAME=(\S+)' IN lv_tname SUBMATCHES lv_typename.
      APPEND VALUE #( name = to_upper( ls_p-parameter ) kind = classify_scalar( lv_typename ) ) TO lt_scalars.
    ENDLOOP.

    APPEND `Field | reference needed | resolution` TO rt_lines.
    APPEND `---|---|---` TO rt_lines.
    LOOP AT lt_hits INTO DATA(ls_hit).
      DATA(lv_need) = COND string( WHEN ls_hit-datatype = 'CURR' THEN 'CUKY (currency key)' ELSE 'UNIT (unit of measure)' ).
      CLEAR lv_resolution.
      " 1) Exact name match: a top-level scalar literally named like the DDIC reference field.
      READ TABLE lt_scalars WITH KEY name = to_upper( ls_hit-reffield ) TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_resolution = |use existing `{ to_upper( ls_hit-reffield ) }` (name matches the DDIC reference field exactly)|.
      ELSE.
        " 2) Domain match: any top-level scalar of the right CUKY/UNIT kind, even
        " under a different local name (what resolved KAWRT/FKIMG - LV_WAERK).
        DATA(lv_want) = COND string( WHEN ls_hit-datatype = 'CURR' THEN 'CUKY' ELSE 'UNIT' ).
        LOOP AT lt_scalars INTO DATA(ls_s) WHERE kind = lv_want.
          lv_resolution = |use existing `{ ls_s-name }` ({ lv_want }-typed, matches by domain not by name)|.
          EXIT.
        ENDLOOP.
      ENDIF.
      IF lv_resolution IS INITIAL.
        lv_resolution = |GAP - no { lv_need } scalar found in this interface; add one (e.g. a global typed { COND #( WHEN ls_hit-datatype = 'CURR' THEN 'WAERK' ELSE 'MEINS' ) })|.
      ENDIF.
      APPEND |`{ ls_hit-owner_type }-{ ls_hit-fieldname }` ({ ls_hit-datatype }) | &&
             |{ lv_need } | &&
             |{ lv_resolution }| TO rt_lines.
    ENDLOOP.
    APPEND `` TO rt_lines.
    APPEND `Domain classification (CUKY/UNIT) depends on CL_ABAP_ELEMDESCR->GET_DDIC_FIELD,` TO rt_lines.
    APPEND `not yet confirmed against a real system - if every "resolution" above says GAP` TO rt_lines.
    APPEND `even for a field you know has a reference (like LV_WAERK here), that call likely` TO rt_lines.
    APPEND `failed silently; fall back to checking by name/eye until confirmed.` TO rt_lines.
  ENDMETHOD.


  METHOD context_build_order.
    DATA lv_n TYPE i.

    IF iv_fm_name IS INITIAL.
      RETURN.
    ENDIF.
    " The classic SSF envelope (S04) is never form-specific and never belongs in Context.
    DATA(lt_standard) = VALUE string_table(
      ( `ARCHIVE_INDEX` ) ( `ARCHIVE_INDEX_TAB` ) ( `ARCHIVE_PARAMETERS` ) ( `CONTROL_PARAMETERS` )
      ( `MAIL_APPL_OBJ` ) ( `MAIL_RECIPIENT` ) ( `MAIL_SENDER` ) ( `OUTPUT_OPTIONS` ) ( `USER_SETTINGS` ) ).

    SELECT parameter, paramtype FROM fupararef
      WHERE funcname = @iv_fm_name AND r3state = 'A' AND ( paramtype = 'I' OR paramtype = 'T' )
      INTO TABLE @DATA(lt_params).
    IF sy-subrc <> 0 OR lt_params IS INITIAL.
      APPEND `(no FUPARAREF rows - confirm manually in SFP's Interface tree)` TO rt_lines.
      RETURN.
    ENDIF.

    LOOP AT lt_params INTO DATA(ls_p).
      READ TABLE lt_standard WITH KEY table_line = to_upper( ls_p-parameter ) TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE. " SSF envelope - SAP generates its own /1BCDWB/DOCPARAMS, never drag this in (S04)
      ENDIF.
      lv_n = lv_n + 1.
      APPEND |{ lv_n }. { ls_p-parameter } ({ COND #( WHEN ls_p-paramtype = 'T' THEN 'table - repeating node' ELSE 'import' ) })| TO rt_lines.
    ENDLOOP.

    IF lv_n = 0.
      APPEND `(every import/table parameter here is part of the standard SSF envelope -` TO rt_lines.
      APPEND `nothing form-specific to drag in; confirm in SFP before assuming Context is empty)` TO rt_lines.
    ENDIF.
  ENDMETHOD.


  METHOD context_struct_fields.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    DATA lt_fields TYPE ddfields.

    TRY.
        lo_struct = CAST cl_abap_structdescr( iv_descr ).
      CATCH cx_root ##CATCH_ALL.
        APPEND |{ iv_param } - { iv_role }; row/structure type isn't a flat structure, confirm manually| TO rt_lines.
        RETURN.
    ENDTRY.
    CALL METHOD lo_struct->get_ddic_field_list
      RECEIVING
        p_field_list = lt_fields
      EXCEPTIONS
        not_found    = 1
        no_ddic_type = 2
        OTHERS       = 3.
    IF sy-subrc <> 0 OR lt_fields IS INITIAL.
      APPEND |{ iv_param } - { iv_role }; field list not resolvable via RTTI, confirm manually| TO rt_lines.
      RETURN.
    ENDIF.
    APPEND |{ iv_param } - { iv_role }, { lines( lt_fields ) } field(s):| TO rt_lines.
    LOOP AT lt_fields INTO DATA(ls_f).
      APPEND |  - { iv_param }-{ ls_f-fieldname }| TO rt_lines.
    ENDLOOP.
  ENDMETHOD.


  METHOD context_node_shapes.
    DATA lo_descr    TYPE REF TO cl_abap_typedescr.
    DATA lv_typename TYPE string.

    IF iv_fm_name IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lt_standard) = VALUE string_table(
      ( `ARCHIVE_INDEX` ) ( `ARCHIVE_INDEX_TAB` ) ( `ARCHIVE_PARAMETERS` ) ( `CONTROL_PARAMETERS` )
      ( `MAIL_APPL_OBJ` ) ( `MAIL_RECIPIENT` ) ( `MAIL_SENDER` ) ( `OUTPUT_OPTIONS` ) ( `USER_SETTINGS` ) ).

    SELECT parameter, paramtype FROM fupararef
      WHERE funcname = @iv_fm_name AND r3state = 'A' AND ( paramtype = 'I' OR paramtype = 'T' )
      INTO TABLE @DATA(lt_params).
    IF sy-subrc <> 0 OR lt_params IS INITIAL.
      APPEND `(no FUPARAREF rows - confirm manually in SFP's Interface tree)` TO rt_lines.
      RETURN.
    ENDIF.

    LOOP AT lt_params INTO DATA(ls_p).
      READ TABLE lt_standard WITH KEY table_line = to_upper( ls_p-parameter ) TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE. " SSF envelope - same exclusion as context_build_order.
      ENDIF.

      DATA(lv_dump) = dump_nonempty( is_row = ls_p it_skip = VALUE string_table( ( `FUNCNAME` ) ( `PARAMETER` ) ( `PARAMTYPE` ) ) ).
      CLEAR lv_typename.
      FIND REGEX 'TYPENAME=(\S+)' IN lv_dump SUBMATCHES lv_typename.
      IF lv_typename IS INITIAL.
        APPEND |{ ls_p-parameter } - TYPENAME not found; confirm shape manually in SFP| TO rt_lines.
        CONTINUE.
      ENDIF.

      CLEAR lo_descr.
      CALL METHOD cl_abap_typedescr=>describe_by_name
        EXPORTING
          p_name         = lv_typename
        RECEIVING
          p_descr_ref    = lo_descr
        EXCEPTIONS
          type_not_found = 1
          OTHERS         = 2.
      IF sy-subrc <> 0 OR lo_descr IS NOT BOUND.
        APPEND |{ ls_p-parameter } - type `{ lv_typename }` not resolvable via RTTI; confirm shape manually in SFP| TO rt_lines.
        CONTINUE.
      ENDIF.

      CASE lo_descr->kind.
        WHEN cl_abap_typedescr=>kind_elem.
          APPEND |{ ls_p-parameter } - CL_FP_DATA (scalar, type { lv_typename })| TO rt_lines.

        WHEN cl_abap_typedescr=>kind_struct.
          APPEND LINES OF context_struct_fields( iv_param = CONV string( ls_p-parameter ) iv_descr = lo_descr iv_role = `CL_FP_STRUCTURE` ) TO rt_lines.

        WHEN cl_abap_typedescr=>kind_table.
          DATA(lo_line) = CAST cl_abap_tabledescr( lo_descr )->get_table_line_type( ).
          IF lo_line->kind = cl_abap_typedescr=>kind_struct.
            APPEND LINES OF context_struct_fields( iv_param = CONV string( ls_p-parameter ) iv_descr = lo_line iv_role = `CL_FP_LOOP/CL_FP_LOOP_DATA` ) TO rt_lines.
          ELSE.
            APPEND |{ ls_p-parameter } - CL_FP_LOOP (type { lv_typename }); row type isn't a flat structure, confirm manually| TO rt_lines.
          ENDIF.

        WHEN OTHERS.
          APPEND |{ ls_p-parameter } - unclassified RTTI kind for type `{ lv_typename }`; confirm manually in SFP| TO rt_lines.
      ENDCASE.
    ENDLOOP.

    IF rt_lines IS INITIAL.
      APPEND `(every import/table parameter here is part of the standard SSF envelope -` TO rt_lines.
      APPEND `nothing form-specific to shape-classify)` TO rt_lines.
    ENDIF.
  ENDMETHOD.


  METHOD dependency_fm_interfaces.
    DATA lt_seen TYPE string_table.
    DATA lv_fm   TYPE string.
    DATA lv_fm30 TYPE char30.

    LOOP AT it_deps INTO DATA(lv_dep).
      CLEAR lv_fm.
      FIND FIRST OCCURRENCE OF REGEX `CALL FUNCTION '([ZY][A-Za-z0-9_/]*)'` IN lv_dep
        IGNORING CASE SUBMATCHES lv_fm.
      IF sy-subrc <> 0 OR lv_fm IS INITIAL.
        CONTINUE.
      ENDIF.
      lv_fm = to_upper( lv_fm ).
      READ TABLE lt_seen WITH KEY table_line = lv_fm TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      APPEND lv_fm TO lt_seen.

      lv_fm30 = lv_fm.
      APPEND |Custom function module `{ lv_fm }` - interface:| TO rt_lines.
      APPEND LINES OF capture_interface( lv_fm30 ) TO rt_lines.
    ENDLOOP.
  ENDMETHOD.


  METHOD capture_volume.
    " COUNT / MAX / MIN on NAST for one application + output type. Read-only;
    " can be slow on a very large NAST - switch "Count NAST usage" off to skip.
    DATA lv_from365 TYPE d.
    DATA lv_from30  TYPE d.
    lv_from365 = sy-datum - 365.
    lv_from30  = sy-datum - 30.

    SELECT COUNT( * ) FROM nast
      WHERE kappl = @iv_kappl AND kschl = @iv_kschl
      INTO @DATA(lv_total).
    IF lv_total = 0.
      APPEND |{ iv_kappl }/{ iv_kschl }: no NAST rows - never output (or archived).| TO rt_lines.
      RETURN.
    ENDIF.

    SELECT COUNT( * ) FROM nast
      WHERE kappl = @iv_kappl AND kschl = @iv_kschl AND erdat >= @lv_from365
      INTO @DATA(lv_365).
    SELECT COUNT( * ) FROM nast
      WHERE kappl = @iv_kappl AND kschl = @iv_kschl AND erdat >= @lv_from30
      INTO @DATA(lv_30).
    SELECT COUNT( * ) FROM nast
      WHERE kappl = @iv_kappl AND kschl = @iv_kschl AND vstat = '1'
      INTO @DATA(lv_ok).
    SELECT MIN( erdat ) FROM nast
      WHERE kappl = @iv_kappl AND kschl = @iv_kschl
      INTO @DATA(lv_first).
    SELECT MAX( erdat ) FROM nast
      WHERE kappl = @iv_kappl AND kschl = @iv_kschl
      INTO @DATA(lv_last).

    APPEND |{ iv_kappl }/{ iv_kschl }: total { lv_total }, last 365 days { lv_365 }, last 30 days { lv_30 }, processed OK { lv_ok }; first { lv_first DATE = ISO }, last { lv_last DATE = ISO }.| TO rt_lines.
  ENDMETHOD.


  METHOD ensure_driver_extracted.
    DATA lv_prog   TYPE tadir-obj_name.
    DATA lt_source TYPE string_table.
    DATA lt_inc    TYPE string_table.

    IF iv_progname IS INITIAL.
      RETURN.
    ENDIF.
    lv_prog = to_upper( iv_progname ).
    IF is_custom( lv_prog ) = abap_false.
      RETURN.
    ENDIF.
    READ TABLE gt_prog_info WITH KEY progname = lv_prog TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

    READ REPORT lv_prog INTO lt_source.
    IF sy-subrc <> 0 OR lt_source IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_file) = write_driver_source( iv_progname = lv_prog it_source = lt_source ).
    DATA(lt_deps) = scan_dependencies( lt_source ).
    extract_includes( EXPORTING it_source        = lt_source
                      CHANGING  ct_include_files = lt_inc
                                ct_deps          = lt_deps ).
    APPEND VALUE #( progname      = lv_prog
                    source_file   = lv_file
                    deps          = lt_deps
                    include_files = lt_inc ) TO gt_prog_info.
  ENDMETHOD.


  METHOD driver_info_lines.
    DATA lv_prog TYPE tadir-obj_name.
    lv_prog = to_upper( iv_progname ).
    DATA(ls_info) = get_prog_info( lv_prog ).
    IF ls_info-source_file IS NOT INITIAL.
      APPEND |  full source extracted to `{ ls_info-source_file }`| TO rt_lines.
    ELSEIF is_custom( lv_prog ) = abap_false.
      APPEND |  `{ lv_prog }` is not a custom (Z/Y) program - standard SAP code, not extracted.| TO rt_lines.
    ELSE.
      APPEND `  (source extraction failed - check authorization to READ REPORT, or the name is a routine/include)` TO rt_lines.
    ENDIF.
    IF ls_info-include_files IS NOT INITIAL.
      APPEND `  included programs extracted (one level deep):` TO rt_lines.
      LOOP AT ls_info-include_files INTO DATA(lv_inc).
        APPEND |    { lv_inc }| TO rt_lines.
      ENDLOOP.
    ENDIF.
    IF ls_info-deps IS NOT INITIAL.
      APPEND `  dependent objects referenced (raw source lines - confirm each one):` TO rt_lines.
      LOOP AT ls_info-deps INTO DATA(lv_dep).
        APPEND |    { lv_dep }| TO rt_lines.
      ENDLOOP.
      APPEND LINES OF dependency_fm_interfaces( ls_info-deps ) TO rt_lines.
    ENDIF.
  ENDMETHOD.


  METHOD capture_output_determination.
    DATA lv_hits TYPE i.
    CLEAR: et_pgnam, et_keys, et_lines.

    SELECT * FROM tnapr INTO TABLE @DATA(lt_tnapr) UP TO 50000 ROWS.
    IF sy-subrc <> 0 OR lt_tnapr IS INITIAL.
      APPEND `(no TNAPR rows read - table may not exist/be authorized here; confirm manually via NACE)` TO et_lines.
      RETURN.
    ENDIF.

    LOOP AT lt_tnapr INTO DATA(ls_row).
      DATA(lt_dump)   = dump_any( ls_row ).
      DATA(lv_joined) = concat_lines_of( table = lt_dump sep = | | ).
      " Exact match on SFORM when the row has one (ZSD_ATC vs ZSD_ATC_NEW);
      " rows with an empty SFORM keep the "name appears in any column" test.
      DATA(lv_is_hit) = abap_false.
      ASSIGN COMPONENT 'SFORM' OF STRUCTURE ls_row TO FIELD-SYMBOL(<lfv_sform>).
      IF sy-subrc = 0 AND <lfv_sform> IS NOT INITIAL.
        IF to_upper( |{ <lfv_sform> }| ) = to_upper( iv_formname ).
          lv_is_hit = abap_true.
        ENDIF.
      ELSEIF lv_joined CS iv_formname.
        lv_is_hit = abap_true.
      ENDIF.
      IF lv_is_hit = abap_true.
        lv_hits = lv_hits + 1.
        APPEND `-` TO et_lines.
        APPEND LINES OF lt_dump TO et_lines.
        " PGNAM (print/driver program) - NACE's own record of the driver.
        IF ls_row-pgnam IS NOT INITIAL.
          APPEND CONV string( ls_row-pgnam ) TO et_pgnam.
        ENDIF.
        ASSIGN COMPONENT 'KAPPL' OF STRUCTURE ls_row TO FIELD-SYMBOL(<lfv_kappl>).
        DATA(lv_kappl_rc) = sy-subrc.
        ASSIGN COMPONENT 'KSCHL' OF STRUCTURE ls_row TO FIELD-SYMBOL(<lfv_kschl>).
        IF lv_kappl_rc = 0 AND sy-subrc = 0.
          APPEND |{ <lfv_kappl> }/{ <lfv_kschl> }| TO et_keys.
        ENDIF.
      ENDIF.
    ENDLOOP.
    SORT et_keys.
    DELETE ADJACENT DUPLICATES FROM et_keys.

    IF lv_hits = 0.
      APPEND `(no TNAPR row mentions this form name - confirm manually via NACE; the` TO et_lines.
      APPEND `output type may reference a driver routine rather than the form name directly)` TO et_lines.
    ENDIF.

    IF et_pgnam IS NOT INITIAL.
      SORT et_pgnam.
      DELETE ADJACENT DUPLICATES FROM et_pgnam.
    ENDIF.
  ENDMETHOD.


  METHOD probe_form_storage.
    DATA lo_struct TYPE REF TO cl_abap_structdescr.
    DATA lo_descr  TYPE REF TO cl_abap_typedescr.
    DATA lr_tab    TYPE REF TO data.
    DATA lv_hits   TYPE i.

    DATA(lt_candidates) = VALUE string_table(
      ( `STXFOBJECT` ) ( `STXFATTR` ) ( `STXFHEADER` ) ( `SSFOBJ` ) ).

    LOOP AT lt_candidates INTO DATA(lv_tab).
      CLEAR: lo_struct, lo_descr, lr_tab.
      " DESCRIBE_BY_NAME's TYPE_NOT_FOUND is classic, non-class-based (F12).
      CALL METHOD cl_abap_typedescr=>describe_by_name
        EXPORTING
          p_name         = lv_tab
        RECEIVING
          p_descr_ref    = lo_descr
        EXCEPTIONS
          type_not_found = 1
          OTHERS         = 2.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      TRY.
          lo_struct = CAST cl_abap_structdescr( lo_descr ).
        CATCH cx_root ##CATCH_ALL.
          CONTINUE.
      ENDTRY.
      IF lo_struct IS NOT BOUND.
        CONTINUE.
      ENDIF.

      TRY.
          DATA(lo_tabtype) = cl_abap_tabledescr=>create(
            p_line_type  = lo_struct
            p_table_kind = cl_abap_tabledescr=>tablekind_std
            p_unique     = abap_false ).
          CREATE DATA lr_tab TYPE HANDLE lo_tabtype.
        CATCH cx_root ##CATCH_ALL.
          CONTINUE.
      ENDTRY.
      ASSIGN lr_tab->* TO FIELD-SYMBOL(<lft_rows>).
      IF <lft_rows> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      TRY.
          SELECT * FROM (lv_tab) INTO TABLE @<lft_rows> UP TO 20000 ROWS.
        CATCH cx_root ##CATCH_ALL.
          CONTINUE.
      ENDTRY.
      IF sy-subrc <> 0 OR <lft_rows> IS INITIAL.
        CONTINUE.
      ENDIF.

      lv_hits = 0.
      LOOP AT <lft_rows> ASSIGNING FIELD-SYMBOL(<lfs_row>).
        DATA(lt_dump)   = dump_any( <lfs_row> ).
        DATA(lv_joined) = concat_lines_of( table = lt_dump sep = | | ).
        IF lv_joined CS iv_formname.
          lv_hits = lv_hits + 1.
          IF lv_hits <= 3.
            APPEND |candidate table { lv_tab } (unverified - confirm relevance):| TO rt_lines.
            APPEND `-` TO rt_lines.
            APPEND LINES OF lt_dump TO rt_lines.
          ENDIF.
        ENDIF.
      ENDLOOP.
      IF lv_hits > 3.
        APPEND |... and { lv_hits - 3 } more row(s) in { lv_tab }| TO rt_lines.
      ENDIF.
    ENDLOOP.

    IF rt_lines IS INITIAL.
      APPEND `(no candidate table matched - these were speculative guesses (STXFOBJECT,` TO rt_lines.
      APPEND `STXFATTR, STXFHEADER, SSFOBJ), tried safely: a wrong table name is skipped,` TO rt_lines.
      APPEND `not fatal. For a DEFINITIVE answer that unlocks safe automation for every` TO rt_lines.
      APPEND `remaining form at once (not just this one) - set an ABAP debugger` TO rt_lines.
      APPEND `breakpoint in SE71 at the point the SmartStyle name loads (or ask an` TO rt_lines.
      APPEND `ABAP/Basis colleague to), inspect which table/field it reads from, and` TO rt_lines.
      APPEND `share that.` TO rt_lines.
    ENDIF.
  ENDMETHOD.


  METHOD process_form.
    DATA lt_drivers TYPE ty_t_driver_hit.

    DATA(lv_fm) = resolve_fm_name( iv_formname ).
    LOOP AT it_idx INTO DATA(ls_idx) WHERE formname = iv_formname.
      APPEND VALUE #( progname = ls_idx-progname ) TO lt_drivers.
    ENDLOOP.

    write_snapshot( iv_formname = iv_formname
                    iv_fm_name  = lv_fm
                    it_drivers  = lt_drivers ).
    w( |{ iv_formname }: FM { COND #( WHEN lv_fm IS INITIAL THEN 'NOT FOUND - check SE71' ELSE lv_fm ) }, | &&
       |{ lines( lt_drivers ) } driver candidate(s).| ).
  ENDMETHOD.


  METHOD write_snapshot.
    DATA lt_lines        TYPE string_table.
    DATA lt_pgnam        TYPE string_table.
    DATA lt_keys         TYPE string_table.
    DATA lt_nace_lines   TYPE string_table.
    DATA lv_is_candidate TYPE abap_bool.
    DATA lv_kappl_s      TYPE string.
    DATA lv_kschl_s      TYPE string.
    DATA lv_kappl        TYPE nast-kappl.
    DATA lv_kschl        TYPE nast-kschl.

    DATA(lv_stamp) = |{ sy-datum+0(4) }-{ sy-datum+4(2) }-{ sy-datum+6(2) } | &&
                     |{ sy-uzeit+0(2) }:{ sy-uzeit+2(2) }:{ sy-uzeit+4(2) }|.

    APPEND |# Legacy Grab - { iv_formname }| TO lt_lines.
    APPEND `` TO lt_lines.
    APPEND |Generated { lv_stamp } by ZSF2AF_R_LEGACY_GRAB (Bolt with Fiori port ZCL_AB_BOLT_LEGACY_GRAB, system { sy-sysid } client { sy-mandt }).| TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND |## 1. Generated function module| TO lt_lines.
    IF iv_fm_name IS INITIAL.
      APPEND `NOT FOUND - form may not exist, or is not active. Check SE71.` TO lt_lines.
    ELSE.
      APPEND |`{ iv_fm_name }`| TO lt_lines.
    ENDIF.
    APPEND `` TO lt_lines.

    APPEND `## 2. Form interface (import/export/tables/exceptions)` TO lt_lines.
    APPEND `Each parameter shows every attribute FUPARAREF carries for it (type/structure,` TO lt_lines.
    APPEND `reference, default, optional ...) - the contract the Adobe interface must keep.` TO lt_lines.
    APPEND LINES OF capture_interface( iv_fm_name ) TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND `### 2b. Custom types used by the interface (DDIC layout)` TO lt_lines.
    DATA(lt_custom_types) = interface_custom_types( iv_fm_name ).
    IF lt_custom_types IS INITIAL.
      APPEND `(no custom Z/Y type named in the interface, or no interface rows read)` TO lt_lines.
    ELSE.
      LOOP AT lt_custom_types INTO DATA(lv_ctype).
        APPEND LINES OF describe_type( lv_ctype ) TO lt_lines.
      ENDLOOP.
    ENDIF.
    APPEND `` TO lt_lines.

    APPEND `### 2c. Currency/quantity reference fields - resolve before building SFPREF` TO lt_lines.
    APPEND `Every CURR/QUAN field found above, with its real DDIC reference field and` TO lt_lines.
    APPEND `whether a top-level scalar already covers it. Read this before writing any` TO lt_lines.
    APPEND `REFERENCE_FIELDS entry - do not infer a field's CURR/QUAN kind from anything` TO lt_lines.
    APPEND `else (a client's rejected reference, a similar-sounding field name, ...) -` TO lt_lines.
    APPEND `this table is the DDIC's own answer. See BUILD_ISSUES_LOG.md F50.` TO lt_lines.
    IF lt_custom_types IS INITIAL.
      APPEND `(no custom types to check - see 2b)` TO lt_lines.
    ELSE.
      APPEND LINES OF capture_reference_requirements( iv_fm_name = iv_fm_name it_custom_types = lt_custom_types ) TO lt_lines.
    ENDIF.
    APPEND `` TO lt_lines.

    APPEND `### 2d. Context build order - drag these, in this order, nothing else to decide` TO lt_lines.
    APPEND `Once the empty interface/form baseline exists in SFP, drag each of these from` TO lt_lines.
    APPEND `the Interface tree into the form's Context, in this order. Where a CURR/QUAN` TO lt_lines.
    APPEND `field is involved, use the reference resolved in section 2c above - if 2c` TO lt_lines.
    APPEND `already declared it in the interface's own Reference Fields, SAP fills it in` TO lt_lines.
    APPEND `for you; only set it by hand if 2c reported a GAP.` TO lt_lines.
    APPEND LINES OF context_build_order( iv_fm_name ) TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND `### 2e. Context node shapes - real DDIC shape + field list for each` TO lt_lines.
    APPEND `Per S04 (confirmed 2026-10-01): CL_FP_DATA (scalar), CL_FP_STRUCTURE and` TO lt_lines.
    APPEND `CL_FP_LOOP/CL_FP_LOOP_DATA (table) are all hand-authorable. This is the real` TO lt_lines.
    APPEND `shape and, for a structure/table, the real field list each parameter in 2d` TO lt_lines.
    APPEND `needs - read from RTTI on the real TYPENAME, not from FUPARAREF's PARAMTYPE` TO lt_lines.
    APPEND `(a calling-convention flag, not a DDIC kind - a table-typed field can sit` TO lt_lines.
    APPEND `under PARAMTYPE='I' same as a scalar) and never a guessed field name.` TO lt_lines.
    APPEND LINES OF context_node_shapes( iv_fm_name ) TO lt_lines.
    APPEND `` TO lt_lines.

    " Authoritative driver identity, captured once so section 3 can be
    " cross-checked against it (ZSD_ATC fix, BUILD_ISSUES_LOG.md).
    capture_output_determination( EXPORTING iv_formname = iv_formname
                                  IMPORTING et_pgnam    = lt_pgnam
                                            et_keys     = lt_keys
                                            et_lines    = lt_nace_lines ).

    " The driver NACE names is the authority - extract its source even when
    " the source scan missed it (the ZSD_ATC case: it calls a wrapper).
    LOOP AT lt_pgnam INTO DATA(lv_pgnam_x).
      ensure_driver_extracted( lv_pgnam_x ).
    ENDLOOP.

    APPEND `## 3. Driver program candidates (source + dependencies extracted)` TO lt_lines.
    IF gv_index_built = abap_false.
      APPEND `Note: the driver source-scan index (report ZABR_BOLT_DRIVER_INDEX) has not been built on` TO lt_lines.
      APPEND `this system yet - only the driver(s) NACE names were extracted below. Build the index` TO lt_lines.
      APPEND `and re-send the files if this form's real driver is not NACE-configured.` TO lt_lines.
    ENDIF.

    APPEND `Driver identity check (NACE/TNAPR PGNAM vs. the source-text scan below):` TO lt_lines.
    IF lt_pgnam IS INITIAL.
      APPEND `NACE/TNAPR (section 4) names no PGNAM for this form - confirm manually` TO lt_lines.
      APPEND `via the NACE Processing Routines tab before trusting any candidate below.` TO lt_lines.
    ELSE.
      LOOP AT lt_pgnam INTO DATA(lv_pgnam_entry).
        lv_is_candidate = abap_false.
        LOOP AT it_drivers INTO DATA(ls_check) WHERE progname = lv_pgnam_entry.
          lv_is_candidate = abap_true.
          EXIT.
        ENDLOOP.

        IF lv_is_candidate = abap_true.
          APPEND |MATCH - NACE names `{ lv_pgnam_entry }`, and the source scan independently| TO lt_lines.
          APPEND |found it below. Still confirm live before treating as final.| TO lt_lines.
        ELSE.
          SELECT SINGLE obj_name FROM tadir
            WHERE pgmid = 'R3TR' AND object = 'PROG' AND obj_name = @lv_pgnam_entry
            INTO @DATA(lv_tadir_hit).
          DATA(lv_pgnam_exists) = xsdbool( sy-subrc = 0 ).

          APPEND |MISMATCH - NACE names `{ lv_pgnam_entry }`, but the source scan did NOT| TO lt_lines.
          IF lv_pgnam_exists = abap_true.
            APPEND |find it (it exists as a program, so it most likely calls a wrapper routine| TO lt_lines.
            APPEND |rather than SSF_FUNCTION_MODULE_NAME directly - read its source manually).| TO lt_lines.
          ELSE.
            APPEND |find it, and it does not exist as a PROG in TADIR either (may be a routine| TO lt_lines.
            APPEND |or include name, not a standalone program). See docs/02_legacy_grab_spec.md| TO lt_lines.
            APPEND |for the debugger-breakpoint fallback.| TO lt_lines.
          ENDIF.
          APPEND |Treat this form's real driver as UNCONFIRMED until resolved with the| TO lt_lines.
          APPEND |functional owner - do not silently pick the nearest candidate below.| TO lt_lines.
          CLEAR lv_tadir_hit.
        ENDIF.
      ENDLOOP.
    ENDIF.
    APPEND `` TO lt_lines.

    IF lt_pgnam IS NOT INITIAL.
      APPEND `Driver(s) named by NACE (authoritative - source extracted regardless of the scan):` TO lt_lines.
      LOOP AT lt_pgnam INTO DATA(lv_nace_prog).
        APPEND |- `{ lv_nace_prog }` (TNAPR-PGNAM)| TO lt_lines.
        APPEND LINES OF driver_info_lines( lv_nace_prog ) TO lt_lines.
      ENDLOOP.
      APPEND `` TO lt_lines.
    ENDIF.

    IF it_drivers IS INITIAL.
      APPEND `None found scanning Z*/Y* programs for a literal match near an` TO lt_lines.
      APPEND `SSF_FUNCTION_MODULE_NAME call. Confirm manually (NACE output-type` TO lt_lines.
      APPEND `Processing Routines tab, or ask the functional owner).` TO lt_lines.
    ELSE.
      LOOP AT it_drivers INTO DATA(ls_hit).
        DATA(ls_info) = get_prog_info( ls_hit-progname ).
        APPEND |- `{ ls_hit-progname }` (source-scan CANDIDATE - form name found near an SSF_FUNCTION_MODULE_NAME call; see the driver identity check above before trusting this. READ-ONLY: never modified - see docs/01_scope.md section 8)| TO lt_lines.
        IF ls_info-source_file IS NOT INITIAL.
          APPEND |  full source extracted to `{ ls_info-source_file }`| TO lt_lines.
        ELSE.
          APPEND `  (source extraction failed for this program - check authorization to READ REPORT)` TO lt_lines.
        ENDIF.
        IF ls_info-include_files IS NOT INITIAL.
          APPEND `  included programs extracted (one level deep):` TO lt_lines.
          LOOP AT ls_info-include_files INTO DATA(lv_inc).
            APPEND |    { lv_inc }| TO lt_lines.
          ENDLOOP.
        ENDIF.
        IF ls_info-deps IS INITIAL.
          APPEND `  no other Z*/Y* object references found by the dependency scan` TO lt_lines.
        ELSE.
          APPEND `  dependent objects referenced (raw source lines, driver + its includes - confirm each one):` TO lt_lines.
          LOOP AT ls_info-deps INTO DATA(lv_dep).
            APPEND |    { lv_dep }| TO lt_lines.
          ENDLOOP.
        ENDIF.
      ENDLOOP.
    ENDIF.
    APPEND `` TO lt_lines.

    APPEND `## 4. Output determination (NACE / TNAPR)` TO lt_lines.
    APPEND LINES OF lt_nace_lines TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND `### 4b. Usage evidence (NAST) - how much is this form really used?` TO lt_lines.
    IF gv_count_volume = abap_false.
      APPEND `(skipped - P_VOL unticked)` TO lt_lines.
    ELSEIF lt_keys IS INITIAL.
      APPEND `(no application/output-type key found in section 4, so nothing to count)` TO lt_lines.
    ELSE.
      LOOP AT lt_keys INTO DATA(lv_key).
        CLEAR: lv_kappl_s, lv_kschl_s.
        SPLIT lv_key AT '/' INTO lv_kappl_s lv_kschl_s.
        lv_kappl = lv_kappl_s.
        lv_kschl = lv_kschl_s.
        TRY.
            APPEND LINES OF capture_volume( iv_kappl = lv_kappl iv_kschl = lv_kschl ) TO lt_lines.
          CATCH cx_root INTO DATA(lx_vol) ##CATCH_ALL.
            APPEND |{ lv_key }: NAST count failed - { lx_vol->get_text( ) }| TO lt_lines.
        ENDTRY.
      ENDLOOP.
    ENDIF.
    APPEND `` TO lt_lines.

    APPEND `## 5. SSF_READ_FORM interface (auto-probed via FUPARAREF, informational only)` TO lt_lines.
    APPEND `Correction: this turned out NOT to be the layout/style/graphic read API -` TO lt_lines.
    APPEND `its EXPORTING fields (CAPTION/VARTEXT/FMNUMB/ACTIVE/ADMDATA) read as form` TO lt_lines.
    APPEND `header/admin metadata, and there is no TABLES parameter for a node tree.` TO lt_lines.
    APPEND `Kept for reference (occasionally useful for description/version) - sections` TO lt_lines.
    APPEND `6-8 stay manual, produced via the SFP "Create Adobe Form by Migration"` TO lt_lines.
    APPEND `wizard instead (see docs/05_individual_form_conversion_framework.md), not a` TO lt_lines.
    APPEND `background read.` TO lt_lines.
    IF gt_ssf_read_form_iface IS INITIAL.
      APPEND `(not probed)` TO lt_lines.
    ELSE.
      APPEND LINES OF gt_ssf_read_form_iface TO lt_lines.
    ENDIF.
    APPEND `` TO lt_lines.

    DATA(lt_storage_probe) = probe_form_storage( iv_formname ).

    APPEND `## 6. SmartStyle(s) used - auto-probe attempted, fallback MANUAL` TO lt_lines.
    APPEND LINES OF lt_storage_probe TO lt_lines.
    APPEND `SE71 -> Form Attributes -> Output Options shows the SmartStyle name this form` TO lt_lines.
    APPEND `uses. It should already be listed in docs/legacy_grab/global_smartstyles.txt` TO lt_lines.
    APPEND `(from the P_GLOB sweep) - just note WHICH one here and match it against` TO lt_lines.
    APPEND `docs/04_global_style_catalogue.md. Only research its format details fresh if` TO lt_lines.
    APPEND `it isn't in the global catalogue yet.` TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND `## 7. Graphics / logos - see the storage probe in section 6` TO lt_lines.
    APPEND `Note any Graphic node in the form's window tree (SE71) and which SE78 object` TO lt_lines.
    APPEND `it points to. It should already be listed in` TO lt_lines.
    APPEND `docs/legacy_grab/global_logos.txt (from the P_GLOB sweep) - just note WHICH` TO lt_lines.
    APPEND `one here and match it against docs/04_global_style_catalogue.md.` TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND `## 8. Form outline (pages / windows / node types) - MANUAL` TO lt_lines.
    APPEND `Walk the SE71 navigation tree and note each page/window/node (text, table,` TO lt_lines.
    APPEND `loop, graphic) as a short outline here.` TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND `## 9. Risk score` TO lt_lines.
    APPEND `Business criticality / Interactivity / Layout complexity / Driver complexity /` TO lt_lines.
    APPEND `Integration touchpoints / Localization / Volume -> composite: Low / Medium / High / Critical.` TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND `## 10. Output comparison (OTF) - Phase 2 pilot only, not auto-captured here` TO lt_lines.
    APPEND `OTF is a rendered print stream, not a design source - it cannot be used to` TO lt_lines.
    APPEND `rebuild the form. Its correct role is validation: once the Adobe Form exists,` TO lt_lines.
    APPEND `run this form for one real document (SSF control param GETOTF = 'X' captures` TO lt_lines.
    APPEND `JOB_OUTPUT_INFO-OTFDATA; CONVERT_OTF renders it to PDF for comparison) and` TO lt_lines.
    APPEND `diff it visually against the new Adobe Form's PDF for the same document.` TO lt_lines.
    APPEND `` TO lt_lines.

    APPEND `## 11. Full prerequisite checklist - confirm every item before converting` TO lt_lines.
    APPEND `[ ] SmartStyle name(s) (section 6)` TO lt_lines.
    APPEND `[ ] Paragraph/character formats used by each SmartStyle` TO lt_lines.
    APPEND `[ ] Graphics/logos referenced (section 7) - MIME Repository object + binary export` TO lt_lines.
    APPEND `[ ] Standard texts (SO10) referenced by any TEXT/INCLUDE TEXT node -` TO lt_lines.
    APPEND `    check each TDOBJECT/TDNAME/TDID/TDSPRAS via SO10` TO lt_lines.
    APPEND `[ ] Barcode / font resources (if the form prints barcodes or labels)` TO lt_lines.
    APPEND `[ ] Languages / translations required (each SPRAS variant, if multi-language)` TO lt_lines.
    APPEND `[ ] Driver program full source (section 3 - extracted)` TO lt_lines.
    APPEND `[ ] Included programs of the driver (section 3 - extracted where found)` TO lt_lines.
    APPEND `[ ] Other custom objects the driver/includes reference (section 3 - confirm each)` TO lt_lines.
    APPEND `[ ] Form interface (section 2 - extracted)` TO lt_lines.
    APPEND `[ ] Output determination / NACE linkage (section 4 - extracted)` TO lt_lines.
    APPEND `[ ] Digital signature / interactive XFA scripting, if this form is interactive` TO lt_lines.
    APPEND `[ ] Authorization checks inside the driver program (read the extracted source)` TO lt_lines.
    APPEND `[ ] Number-range/posting side effects inside the driver (read the extracted source)` TO lt_lines.

    add_file( iv_name = |{ iv_formname }.md| iv_kind = `SNAPSHOT` it_lines = lt_lines ).
  ENDMETHOD.


  METHOD global_sweep.
    DATA lt_style_out TYPE string_table.
    DATA lt_logo_out  TYPE string_table.

    CLEAR: gt_files, gt_log.
    w( `Global prerequisites sweep starting (SmartStyles + SE78 graphics)...` ).

    " SmartStyles: TADIR object type SSST, both prefixes.
    DATA(lv_pattern)  = gv_pref1 && '%'.
    DATA(lv_pattern2) = COND string( WHEN gv_pref2 IS INITIAL THEN lv_pattern ELSE gv_pref2 && '%' ).
    SELECT obj_name FROM tadir
      WHERE pgmid = 'R3TR' AND object = 'SSST'
        AND ( obj_name LIKE @lv_pattern OR obj_name LIKE @lv_pattern2 )
      ORDER BY obj_name
      INTO TABLE @DATA(lt_tadir_style).
    DATA(lv_style_rc) = sy-subrc.

    APPEND `# Global SmartStyle inventory` TO lt_style_out.
    APPEND `` TO lt_style_out.
    APPEND `TADIR object type SSST, best effort - verify count against` TO lt_style_out.
    APPEND `SMARTSTYLES/SE71 the first time this is run.` TO lt_style_out.
    APPEND `` TO lt_style_out.
    IF lv_style_rc <> 0 OR lt_tadir_style IS INITIAL.
      APPEND `(none found - verify object type SSST in SE16/SMARTSTYLES, or list manually)` TO lt_style_out.
      w( `SmartStyle inventory: 0 found via TADIR SSST - verify the object type, or list manually.` ).
    ELSE.
      LOOP AT lt_tadir_style INTO DATA(ls_style).
        APPEND |- { ls_style-obj_name }| TO lt_style_out.
      ENDLOOP.
      w( |SmartStyle inventory: { lines( lt_tadir_style ) } found.| ).
    ENDIF.
    add_file( iv_name = `global_smartstyles.txt` iv_kind = `GLOBAL` it_lines = lt_style_out ).

    " Graphics/logos: SE78-registered, table STXBITMAPS, SELECT * (no field-name guess).
    SELECT * FROM stxbitmaps INTO TABLE @DATA(lt_bitmaps) UP TO 10000 ROWS.
    DATA(lv_bmp_rc) = sy-subrc.

    APPEND `# Global logo/graphic inventory (SE78 / STXBITMAPS)` TO lt_logo_out.
    APPEND `` TO lt_logo_out.
    IF lv_bmp_rc <> 0 OR lt_bitmaps IS INITIAL.
      APPEND `(no STXBITMAPS rows read - table may not exist/be authorized here;` TO lt_logo_out.
      APPEND `list manually via SE78)` TO lt_logo_out.
      w( `Logo inventory: STXBITMAPS read failed or empty - see file for manual fallback.` ).
    ELSE.
      LOOP AT lt_bitmaps INTO DATA(ls_bmp).
        APPEND `-` TO lt_logo_out.
        APPEND LINES OF dump_any( ls_bmp ) TO lt_logo_out.
      ENDLOOP.
      w( |Logo inventory: { lines( lt_bitmaps ) } row(s) found.| ).
    ENDIF.
    add_file( iv_name = `global_logos.txt` iv_kind = `GLOBAL` it_lines = lt_logo_out ).

    rt_files = gt_files.
  ENDMETHOD.

ENDCLASS.
