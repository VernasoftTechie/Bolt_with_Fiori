"! <p class="shorttext synchronized">Bolt with Fiori - configuration access</p>
"! Read-only access to the setup row, the source systems and the stored
"! secret, plus the shared constants every other class uses. Writes happen
"! only through the RAP business objects (ZI_BOLT_SETUP / ZI_BOLT_SYSTEM).
CLASS zcl_bolt_config DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES ty_t_system TYPE SORTED TABLE OF zbolt_system WITH UNIQUE KEY system_id.

    CONSTANTS:
      gc_setup_id         TYPE zbolt_setup-setup_id     VALUE 'DEFAULT',
      gc_secret_ai_key    TYPE zbolt_secret-secret_id   VALUE 'AI_KEY',
      gc_default_prefix   TYPE zbolt_setup-gh_branch_prefix VALUE 'vernasofttechie',
      gc_default_base     TYPE zbolt_setup-gh_base_branch   VALUE 'main',
      gc_default_path     TYPE zbolt_system-service_path
                          VALUE '/sap/opu/odata4/sap/zbolt_ui_o4/srvd/sap/zbolt_ui/0001/',
      gc_provider_none    TYPE zbolt_setup-ai_provider  VALUE 'NONE',
      gc_provider_openai  TYPE zbolt_setup-ai_provider  VALUE 'OPENAI',
      gc_provider_claude  TYPE zbolt_setup-ai_provider  VALUE 'ANTHROPIC',
      gc_ok               TYPE zbolt_setup-gh_status    VALUE 'OK',
      gc_error            TYPE zbolt_setup-gh_status    VALUE 'ERROR'.

    CONSTANTS:
      BEGIN OF gc_push,
        pending   TYPE zbolt_mig-push_status VALUE 'PENDING',
        pushed    TYPE zbolt_mig-push_status VALUE 'PUSHED',
        failed    TYPE zbolt_mig-push_status VALUE 'FAILED',
        withdrawn TYPE zbolt_mig-push_status VALUE 'WITHDRAWN',
      END OF gc_push.

    "! The setup row (SETUP_ID = DEFAULT). Initial when the app was never set up.
    CLASS-METHODS get_setup
      RETURNING VALUE(rs_setup) TYPE zbolt_setup.

    CLASS-METHODS get_system
      IMPORTING iv_system_id     TYPE zbolt_system-system_id
      RETURNING VALUE(rs_system) TYPE zbolt_system.

    CLASS-METHODS get_systems
      RETURNING VALUE(rt_systems) TYPE ty_t_system.

    "! The system flagged default, else the local one, else the first.
    CLASS-METHODS get_default_system
      RETURNING VALUE(rs_system) TYPE zbolt_system.

    "! True when ADMIN_USERS is blank (everyone administers) or lists the user.
    CLASS-METHODS is_admin
      IMPORTING iv_user         TYPE syuname DEFAULT sy-uname
      RETURNING VALUE(rv_admin) TYPE abap_bool.

    CLASS-METHODS get_secret
      IMPORTING iv_secret_id    TYPE zbolt_secret-secret_id
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS now
      RETURNING VALUE(rv_ts) TYPE timestampl.

    "! Current UTC time as 2026-11-18T10:42:00.123Z (same as JavaScript toISOString).
    CLASS-METHODS iso_now
      RETURNING VALUE(rv_iso) TYPE string.

    "! Custom name prefixes of the setup as 'Z,Y'.
    CLASS-METHODS prefixes
      IMPORTING is_setup           TYPE zbolt_setup
      RETURNING VALUE(rv_prefixes) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zcl_bolt_config IMPLEMENTATION.

  METHOD get_setup.
    SELECT SINGLE * FROM zbolt_setup
      WHERE setup_id = @gc_setup_id
      INTO @rs_setup.
    IF sy-subrc <> 0.
      CLEAR rs_setup.
    ENDIF.
  ENDMETHOD.


  METHOD get_system.
    SELECT SINGLE * FROM zbolt_system
      WHERE system_id = @iv_system_id
      INTO @rs_system.
    IF sy-subrc <> 0.
      CLEAR rs_system.
    ENDIF.
  ENDMETHOD.


  METHOD get_systems.
    SELECT * FROM zbolt_system
      ORDER BY system_id
      INTO TABLE @rt_systems.
  ENDMETHOD.


  METHOD get_default_system.
    DATA(lt_systems) = get_systems( ).
    LOOP AT lt_systems INTO DATA(ls_system) WHERE is_default = abap_true.
      rs_system = ls_system.
      RETURN.
    ENDLOOP.
    LOOP AT lt_systems INTO ls_system WHERE is_local = abap_true.
      rs_system = ls_system.
      RETURN.
    ENDLOOP.
    LOOP AT lt_systems INTO ls_system.
      rs_system = ls_system.
      RETURN.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_admin.
    DATA(ls_setup) = get_setup( ).
    DATA(lv_list) = condense( to_upper( CONV string( ls_setup-admin_users ) ) ).
    IF lv_list IS INITIAL.
      rv_admin = abap_true.
      RETURN.
    ENDIF.
    SPLIT lv_list AT ',' INTO TABLE DATA(lt_users).
    LOOP AT lt_users INTO DATA(lv_user).
      IF condense( lv_user ) = to_upper( CONV string( iv_user ) ).
        rv_admin = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
    rv_admin = abap_false.
  ENDMETHOD.


  METHOD get_secret.
    SELECT SINGLE secret_value FROM zbolt_secret
      WHERE secret_id = @iv_secret_id
      INTO @rv_value.
    IF sy-subrc <> 0.
      CLEAR rv_value.
    ENDIF.
  ENDMETHOD.


  METHOD now.
    GET TIME STAMP FIELD rv_ts.
  ENDMETHOD.


  METHOD iso_now.
    DATA lv_ts  TYPE timestampl.
    DATA lv_txt TYPE c LENGTH 30.
    GET TIME STAMP FIELD lv_ts.
    lv_txt = |{ lv_ts DECIMALS = 3 }|.
    CONDENSE lv_txt NO-GAPS.
    rv_iso = |{ lv_txt(4) }-{ lv_txt+4(2) }-{ lv_txt+6(2) }T{ lv_txt+8(2) }:{ lv_txt+10(2) }:{ lv_txt+12(2) }.{ lv_txt+15(3) }Z|.
  ENDMETHOD.


  METHOD prefixes.
    DATA(lv_p1) = condense( CONV string( is_setup-form_prefix1 ) ).
    DATA(lv_p2) = condense( CONV string( is_setup-form_prefix2 ) ).
    IF lv_p1 IS INITIAL AND lv_p2 IS INITIAL.
      rv_prefixes = `Z,Y`.
    ELSEIF lv_p2 IS INITIAL.
      rv_prefixes = lv_p1.
    ELSEIF lv_p1 IS INITIAL.
      rv_prefixes = lv_p2.
    ELSE.
      rv_prefixes = |{ lv_p1 },{ lv_p2 }|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
