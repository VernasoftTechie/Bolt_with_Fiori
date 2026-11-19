"! <p class="shorttext synchronized">Bolt - Smart Forms of this system</p>
"! The Smart Forms the app offers for migration: every current (not deleted)
"! custom Smart Form of THIS system - the one the Fiori app is launched in -
"! with description, package, last change, the output types that print it
"! (NACE, table TNAPR) and its driver programs (NACE program plus the driver
"! index built by report ZABR_BOLT_DRIVER_INDEX).
"! Smart Forms are cross-client repository objects, so the list is the same in
"! every client of the system; NACE is client-specific customizing and is read
"! in the logon client.
CLASS zcl_ab_bolt_form_catalog DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_form,
        form_name    TYPE tdsfname,
        description  TYPE string,
        dev_package  TYPE devclass,
        created_by   TYPE syuname,
        created_on   TYPE d,
        changed_by   TYPE syuname,
        changed_on   TYPE d,
        driver_progs TYPE string,
        output_types TYPE string,
      END OF ty_form,
      ty_t_form TYPE SORTED TABLE OF ty_form WITH UNIQUE KEY form_name.

    "! All custom Smart Forms (name starts with one of the setup's prefixes).
    CLASS-METHODS list
      IMPORTING iv_prefix1      TYPE string
                iv_prefix2      TYPE string
      RETURNING VALUE(rt_forms) TYPE ty_t_form.

    "! One form, initial when it does not exist (or is deleted) on this system.
    CLASS-METHODS get
      IMPORTING iv_form_name   TYPE csequence
      RETURNING VALUE(rs_form) TYPE ty_form.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_nace,
        form_name TYPE tdsfname,
        programs  TYPE string,
        keys      TYPE string,
      END OF ty_nace,
      ty_t_nace TYPE SORTED TABLE OF ty_nace WITH UNIQUE KEY form_name.

    CLASS-METHODS read
      IMPORTING it_names        TYPE string_table OPTIONAL
                iv_pattern1     TYPE string OPTIONAL
                iv_pattern2     TYPE string OPTIONAL
      RETURNING VALUE(rt_forms) TYPE ty_t_form.

    CLASS-METHODS nace
      RETURNING VALUE(rt_nace) TYPE ty_t_nace.

    CLASS-METHODS add_unique
      IMPORTING iv_item TYPE string
      CHANGING  cv_list TYPE string.
ENDCLASS.



CLASS zcl_ab_bolt_form_catalog IMPLEMENTATION.

  METHOD list.
    DATA(lv_p1) = to_upper( condense( iv_prefix1 ) ).
    DATA(lv_p2) = to_upper( condense( iv_prefix2 ) ).
    IF lv_p1 IS INITIAL.
      lv_p1 = `Z`.
    ENDIF.
    rt_forms = read( iv_pattern1 = lv_p1 && `%`
                     iv_pattern2 = COND #( WHEN lv_p2 IS INITIAL THEN lv_p1 && `%` ELSE lv_p2 && `%` ) ).
  ENDMETHOD.


  METHOD get.
    DATA(lv_name) = to_upper( condense( CONV string( iv_form_name ) ) ).
    DATA(lt_forms) = read( it_names = VALUE #( ( lv_name ) ) ).
    READ TABLE lt_forms INTO rs_form INDEX 1.
    IF sy-subrc <> 0.
      CLEAR rs_form.
    ENDIF.
  ENDMETHOD.


  METHOD add_unique.
    IF iv_item IS INITIAL.
      RETURN.
    ENDIF.
    SPLIT cv_list AT `, ` INTO TABLE DATA(lt_items).
    IF line_exists( lt_items[ table_line = iv_item ] ).
      RETURN.
    ENDIF.
    cv_list = COND #( WHEN cv_list IS INITIAL THEN iv_item ELSE |{ cv_list }, { iv_item }| ).
  ENDMETHOD.


  METHOD nace.
    " TNAPR (processing programs for output) - SFORM names the Smart Form.
    " Read generically: the column set differs slightly between releases.
    DATA lt_tnapr TYPE STANDARD TABLE OF tnapr WITH EMPTY KEY.
    TRY.
        SELECT * FROM tnapr INTO TABLE @lt_tnapr UP TO 50000 ROWS.
      CATCH cx_root ##CATCH_ALL.
        CLEAR lt_tnapr.
    ENDTRY.
    LOOP AT lt_tnapr ASSIGNING FIELD-SYMBOL(<lfs_tnapr>).
      ASSIGN COMPONENT 'SFORM' OF STRUCTURE <lfs_tnapr> TO FIELD-SYMBOL(<lfv_sform>).
      IF sy-subrc <> 0 OR <lfv_sform> IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(lv_form) = CONV tdsfname( to_upper( |{ <lfv_sform> }| ) ).
      DATA(lv_key)  = |{ <lfs_tnapr>-kappl }/{ <lfs_tnapr>-kschl }|.
      DATA(lv_prog) = condense( CONV string( <lfs_tnapr>-pgnam ) ).
      IF NOT line_exists( rt_nace[ form_name = lv_form ] ).
        rt_nace = VALUE #( BASE rt_nace ( form_name = lv_form ) ).
      ENDIF.
      ASSIGN rt_nace[ form_name = lv_form ] TO FIELD-SYMBOL(<lfs_nace>).
      add_unique( EXPORTING iv_item = lv_key  CHANGING cv_list = <lfs_nace>-keys ).
      add_unique( EXPORTING iv_item = lv_prog CHANGING cv_list = <lfs_nace>-programs ).
      UNASSIGN <lfs_nace>.
    ENDLOOP.
  ENDMETHOD.


  METHOD read.
    TYPES:
      BEGIN OF ty_tadir,
        obj_name   TYPE sobj_name,
        devclass   TYPE devclass,
        author     TYPE responsibl,
        created_on TYPE creationdt,
      END OF ty_tadir.
    DATA lt_tadir TYPE STANDARD TABLE OF ty_tadir WITH EMPTY KEY.
    DATA lt_names TYPE RANGE OF sobj_name.
    DATA lt_forms TYPE STANDARD TABLE OF ty_form WITH EMPTY KEY.

    IF it_names IS NOT INITIAL.
      lt_names = VALUE #( FOR lv_n IN it_names ( sign = 'I' option = 'EQ' low = lv_n ) ).
      SELECT obj_name, devclass, author, created_on FROM tadir
        WHERE pgmid = 'R3TR' AND object = 'SSFO' AND delflag = @space
          AND obj_name IN @lt_names
        ORDER BY obj_name
        INTO TABLE @lt_tadir.
    ELSE.
      SELECT obj_name, devclass, author, created_on FROM tadir
        WHERE pgmid = 'R3TR' AND object = 'SSFO' AND delflag = @space
          AND ( obj_name LIKE @iv_pattern1 OR obj_name LIKE @iv_pattern2 )
        ORDER BY obj_name
        INTO TABLE @lt_tadir.
    ENDIF.
    IF lt_tadir IS INITIAL.
      RETURN.
    ENDIF.

    " Last change and description: Smart Form administration tables. Read
    " dynamically and guarded - a different layout on some release only leaves
    " those columns blank.
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
    DATA lt_adm    TYPE SORTED TABLE OF ty_adm WITH NON-UNIQUE KEY formname.
    DATA lt_txt    TYPE SORTED TABLE OF ty_txt WITH NON-UNIQUE KEY formname.
    DATA lv_tab    TYPE string.
    DATA lv_fields TYPE string.
    DATA lv_where  TYPE string.
    TRY.
        lv_tab    = `STXFADM`.
        lv_fields = `FORMNAME, LASTUSER, LASTDATE`.
        " Select list in the order of TY_ADM's components (no INTO CORRESPONDING).
        SELECT (lv_fields) FROM (lv_tab) INTO TABLE @lt_adm.
      CATCH cx_root ##CATCH_ALL.
        CLEAR lt_adm.
    ENDTRY.
    TRY.
        lv_tab    = `STXFADMT`.
        lv_fields = `FORMNAME, CAPTION`.
        lv_where  = |LANGU = '{ sy-langu }'|.
        SELECT (lv_fields) FROM (lv_tab) WHERE (lv_where) INTO TABLE @lt_txt.
      CATCH cx_root ##CATCH_ALL.
        CLEAR lt_txt.
    ENDTRY.

    DATA(lt_nace) = nace( ).
    SELECT form_name, prog_name FROM zabt_bolt_drvix
      ORDER BY form_name, prog_name
      INTO TABLE @DATA(lt_index).

    LOOP AT lt_tadir INTO DATA(ls_tadir).
      DATA(ls_form) = VALUE ty_form( form_name   = CONV #( ls_tadir-obj_name )
                                     dev_package = ls_tadir-devclass
                                     created_by  = CONV #( ls_tadir-author )
                                     created_on  = ls_tadir-created_on ).
      READ TABLE lt_adm INTO DATA(ls_adm) WITH TABLE KEY formname = ls_form-form_name.
      IF sy-subrc = 0.
        ls_form-changed_by = ls_adm-lastuser.
        ls_form-changed_on = ls_adm-lastdate.
      ENDIF.
      READ TABLE lt_txt INTO DATA(ls_txt) WITH TABLE KEY formname = ls_form-form_name.
      IF sy-subrc = 0.
        ls_form-description = condense( CONV string( ls_txt-caption ) ).
      ENDIF.
      READ TABLE lt_nace INTO DATA(ls_nace) WITH TABLE KEY form_name = ls_form-form_name.
      IF sy-subrc = 0.
        ls_form-output_types = ls_nace-keys.
        ls_form-driver_progs = ls_nace-programs.
      ENDIF.
      LOOP AT lt_index INTO DATA(ls_index) WHERE form_name = ls_form-form_name.
        add_unique( EXPORTING iv_item = condense( CONV string( ls_index-prog_name ) )
                    CHANGING  cv_list = ls_form-driver_progs ).
      ENDLOOP.
      APPEND ls_form TO lt_forms.
      CLEAR: ls_adm, ls_txt, ls_nace.
    ENDLOOP.
    SORT lt_forms BY form_name.
    DELETE ADJACENT DUPLICATES FROM lt_forms COMPARING form_name.
    rt_forms = lt_forms.
  ENDMETHOD.

ENDCLASS.
