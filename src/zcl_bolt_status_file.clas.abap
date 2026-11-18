"! <p class="shorttext synchronized">Bolt with Fiori - branch status file read/write</p>
"! ABAP port of Bolt Console's statusParse.js / statusFile.js. One markdown
"! file per migration, docs/legacy_grab/<slug>_status.md on its own branch,
"! is the only point of contact between the client and the engineer:
"!
"!   # Migration Status - <form>
"!   STATUS: / UPDATED: / WAITING_ON: / NOTE: / STOP: / CLAIMED_BY:
"!   ---
"!   ## <ISO time> - <heading>
"!   <text>
"!
"! (the dashes are em dashes in the file). The format must stay byte-for-byte
"! what the engineer windows and tools/queue.mjs parse - change nothing here
"! without changing statusParse.js the same way. Pure: no DB, no HTTP.
CLASS zcl_bolt_status_file DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_entry,
        at      TYPE string,
        heading TYPE string,
        text    TYPE string,
      END OF ty_entry,
      ty_t_entry TYPE STANDARD TABLE OF ty_entry WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_status,
        title      TYPE string,
        status     TYPE string,
        updated_at TYPE string,
        waiting_on TYPE string,
        note       TYPE string,
        stop       TYPE abap_bool,
        claimed_by TYPE string,
        label      TYPE string,
        body       TYPE string,
      END OF ty_status.

    "! Header changes for append_entry - a field is written only when its set_ flag is on.
    TYPES:
      BEGIN OF ty_change,
        status         TYPE string,
        set_status     TYPE abap_bool,
        waiting_on     TYPE string,
        set_waiting_on TYPE abap_bool,
        note           TYPE string,
        set_note       TYPE abap_bool,
        stop           TYPE abap_bool,
        set_stop       TYPE abap_bool,
      END OF ty_change.

    "! Em dash (U+2014) - used in the title line and in every entry heading.
    CONSTANTS gc_dash TYPE string VALUE `—`.

    CLASS-METHODS file_path
      IMPORTING iv_form_slug   TYPE string
      RETURNING VALUE(rv_path) TYPE string.

    CLASS-METHODS parse
      IMPORTING iv_text          TYPE string
      RETURNING VALUE(rs_status) TYPE ty_status.

    "! Splits the body into its "## <at> - <heading>" entries, oldest first.
    CLASS-METHODS timeline
      IMPORTING iv_body           TYPE string
      RETURNING VALUE(rt_entries) TYPE ty_t_entry.

    "! Rebuilds the whole file; UPDATED is always set to now.
    CLASS-METHODS build
      IMPORTING is_status      TYPE ty_status
      RETURNING VALUE(rv_text) TYPE string.

    "! Appends one timeline entry. Header fields whose set_ flag is off keep
    "! their value from the existing file (same rule as appendStatusEntry,
    "! where "undefined" keeps the old value). CLAIMED_BY is never changed -
    "! only an engineer claims or releases.
    CLASS-METHODS append_entry
      IMPORTING iv_existing    TYPE string
                iv_title       TYPE string
                iv_heading     TYPE string
                iv_entry_text  TYPE string
                is_change      TYPE ty_change OPTIONAL
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS label_for
      IMPORTING iv_status       TYPE string
      RETURNING VALUE(rv_label) TYPE string.

    "! Same as migrationBranchName(displayName, prefix) in git.js.
    CLASS-METHODS branch_name
      IMPORTING iv_display_name  TYPE string
                iv_prefix        TYPE string
      RETURNING VALUE(rv_branch) TYPE string.

    "! Same as formSlug() in agent.js.
    CLASS-METHODS form_slug
      IMPORTING iv_form_name   TYPE string
      RETURNING VALUE(rv_slug) TYPE string.

    "! JavaScript String.prototype.trim(): leading/trailing blanks, tabs and line breaks.
    CLASS-METHODS trim
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-METHODS slugify
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_slug) TYPE string.

    CLASS-METHODS split_lines
      IMPORTING iv_text         TYPE string
      RETURNING VALUE(rt_lines) TYPE string_table.
ENDCLASS.



CLASS zcl_bolt_status_file IMPLEMENTATION.

  METHOD file_path.
    rv_path = |docs/legacy_grab/{ iv_form_slug }_status.md|.
  ENDMETHOD.


  METHOD trim.
    DATA(lv_ws)  = | \n\r\t|.
    DATA(lv_len) = strlen( iv_text ).
    DATA(lv_from) = 0.
    WHILE lv_from < lv_len.
      IF substring( val = iv_text off = lv_from len = 1 ) CA lv_ws.
        lv_from += 1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    DATA(lv_to) = lv_len.
    WHILE lv_to > lv_from.
      IF substring( val = iv_text off = lv_to - 1 len = 1 ) CA lv_ws.
        lv_to -= 1.
      ELSE.
        EXIT.
      ENDIF.
    ENDWHILE.
    rv_text = substring( val = iv_text off = lv_from len = lv_to - lv_from ).
  ENDMETHOD.


  METHOD split_lines.
    DATA(lv_text) = iv_text.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_text WITH cl_abap_char_utilities=>newline.
    SPLIT lv_text AT cl_abap_char_utilities=>newline INTO TABLE rt_lines.
  ENDMETHOD.


  METHOD parse.
    DATA lv_key   TYPE string.
    DATA lv_value TYPE string.

    DATA(lt_lines) = split_lines( iv_text ).
    DATA(lv_body_start) = lines( lt_lines ) + 1.

    LOOP AT lt_lines INTO DATA(lv_line).
      DATA(lv_index) = sy-tabix.

      IF find( val = lv_line sub = `# Migration Status` ) = 0.
        DATA(lv_title_pos) = find( val = lv_line sub = gc_dash ).
        IF lv_title_pos >= 0.
          rs_status-title = trim( substring( val = lv_line off = lv_title_pos + strlen( gc_dash ) ) ).
        ENDIF.
      ENDIF.

      CLEAR: lv_key, lv_value.
      FIND FIRST OCCURRENCE OF REGEX '^([A-Z_]+):\s*(.*)$' IN lv_line SUBMATCHES lv_key lv_value.
      IF sy-subrc = 0.
        DATA(lv_val) = trim( lv_value ).
        CASE lv_key.
          WHEN 'STATUS'.
            rs_status-status = lv_val.
          WHEN 'UPDATED'.
            rs_status-updated_at = lv_val.
          WHEN 'WAITING_ON'.
            rs_status-waiting_on = COND #( WHEN lv_val = `none` THEN `` ELSE lv_val ).
          WHEN 'NOTE'.
            rs_status-note = lv_val.
          WHEN 'STOP'.
            rs_status-stop = xsdbool( lv_val = `requested` ).
          WHEN 'CLAIMED_BY'.
            rs_status-claimed_by = COND #( WHEN lv_val = `none` THEN `` ELSE lv_val ).
        ENDCASE.
      ENDIF.

      IF trim( lv_line ) = `---`.
        lv_body_start = lv_index + 1.
        EXIT.
      ENDIF.
    ENDLOOP.

    DATA lt_body TYPE string_table.
    LOOP AT lt_lines INTO lv_line FROM lv_body_start.
      APPEND lv_line TO lt_body.
    ENDLOOP.
    rs_status-body  = trim( concat_lines_of( table = lt_body sep = cl_abap_char_utilities=>newline ) ).
    rs_status-label = label_for( rs_status-status ).
  ENDMETHOD.


  METHOD timeline.
    DATA ls_entry TYPE ty_entry.
    DATA lt_text  TYPE string_table.
    DATA lv_open  TYPE abap_bool.

    DATA(lv_sep_text) = | { gc_dash } |.
    DATA(lt_lines) = split_lines( iv_body ).

    LOOP AT lt_lines INTO DATA(lv_line).
      IF strlen( lv_line ) >= 3 AND substring( val = lv_line len = 3 ) = `## `.
        IF lv_open = abap_true.
          ls_entry-text = trim( concat_lines_of( table = lt_text sep = cl_abap_char_utilities=>newline ) ).
          APPEND ls_entry TO rt_entries.
        ENDIF.
        CLEAR: ls_entry, lt_text.
        lv_open = abap_true.
        DATA(lv_head) = substring( val = lv_line off = 3 ).
        DATA(lv_sep) = find( val = lv_head sub = lv_sep_text ).
        IF lv_sep >= 0.
          ls_entry-at      = substring( val = lv_head len = lv_sep ).
          ls_entry-heading = trim( substring( val = lv_head off = lv_sep + strlen( lv_sep_text ) ) ).
        ELSE.
          ls_entry-heading = trim( lv_head ).
        ENDIF.
      ELSEIF lv_open = abap_true.
        APPEND lv_line TO lt_text.
      ELSEIF trim( lv_line ) IS NOT INITIAL.
        " Text before the first heading - kept as an entry of its own, like parseTimeline.
        lv_open = abap_true.
        ls_entry-heading = substring( val = lv_line len = nmin( val1 = 80 val2 = strlen( lv_line ) ) ).
        APPEND lv_line TO lt_text.
      ENDIF.
    ENDLOOP.

    IF lv_open = abap_true.
      ls_entry-text = trim( concat_lines_of( table = lt_text sep = cl_abap_char_utilities=>newline ) ).
      APPEND ls_entry TO rt_entries.
    ENDIF.
  ENDMETHOD.


  METHOD build.
    DATA(lt_header) = VALUE string_table(
      ( |# Migration Status { gc_dash } { is_status-title }| )
      ( `` )
      ( |STATUS: { is_status-status }| )
      ( |UPDATED: { zcl_bolt_config=>iso_now( ) }| )
      ( |WAITING_ON: { COND string( WHEN is_status-waiting_on IS INITIAL THEN `none` ELSE is_status-waiting_on ) }| )
      ( |NOTE: { is_status-note }| )
      ( |STOP: { COND string( WHEN is_status-stop = abap_true THEN `requested` ELSE `none` ) }| )
      ( |CLAIMED_BY: { COND string( WHEN is_status-claimed_by IS INITIAL THEN `none` ELSE is_status-claimed_by ) }| )
      ( `` )
      ( `---` )
      ( `` ) ).
    " Joined exactly like the JavaScript header (...'---', ''].join('\n')): the
    " last empty element leaves one line break after '---', then the body.
    rv_text = concat_lines_of( table = lt_header sep = cl_abap_char_utilities=>newline ) && is_status-body.
  ENDMETHOD.


  METHOD append_entry.
    DATA ls_old TYPE ty_status.
    DATA ls_new TYPE ty_status.
    DATA(lv_nl) = cl_abap_char_utilities=>newline.

    IF iv_existing IS NOT INITIAL.
      ls_old = parse( iv_existing ).
    ENDIF.

    DATA(lv_entry) = |## { zcl_bolt_config=>iso_now( ) } { gc_dash } { iv_heading }{ lv_nl }{ iv_entry_text }|.
    ls_new-title = iv_title.
    ls_new-body  = COND #( WHEN ls_old-body IS NOT INITIAL
                           THEN |{ ls_old-body }{ lv_nl }{ lv_nl }{ lv_entry }|
                           ELSE lv_entry ).
    IF is_change-set_status = abap_true.
      ls_new-status = is_change-status.
    ELSEIF ls_old-status IS NOT INITIAL.
      ls_new-status = ls_old-status.
    ELSE.
      ls_new-status = `queued`.
    ENDIF.
    ls_new-waiting_on = COND #( WHEN is_change-set_waiting_on = abap_true THEN is_change-waiting_on ELSE ls_old-waiting_on ).
    ls_new-note       = COND #( WHEN is_change-set_note = abap_true THEN is_change-note ELSE ls_old-note ).
    ls_new-stop       = COND #( WHEN is_change-set_stop = abap_true THEN is_change-stop ELSE ls_old-stop ).
    ls_new-claimed_by = ls_old-claimed_by.

    rv_text = build( ls_new ).
  ENDMETHOD.


  METHOD label_for.
    rv_label = SWITCH #( iv_status
      WHEN `queued`              THEN `Queued`
      WHEN `in_progress`         THEN `In Progress`
      WHEN `interface_completed` THEN `Interface Completed`
      WHEN `waiting_manual`      THEN |Waiting { gc_dash } Manual Activity|
      WHEN `layout_in_progress`  THEN `Form Design In Progress`
      WHEN `completed`           THEN `Migration Completed`
      WHEN `open_for_concerns`   THEN |Open { gc_dash } Awaiting Review|
      WHEN ``                    THEN `Unknown`
      ELSE iv_status ).
  ENDMETHOD.


  METHOD slugify.
    DATA(lv_text) = to_lower( trim( iv_text ) ).
    REPLACE ALL OCCURRENCES OF REGEX '[^a-z0-9._-]+' IN lv_text WITH '-'.
    REPLACE ALL OCCURRENCES OF REGEX '-+' IN lv_text WITH '-'.
    " Strip leading/trailing separators (- . _) the way git.js does.
    DATA(lv_len) = strlen( lv_text ).
    DATA(lv_from) = 0.
    WHILE lv_from < lv_len AND substring( val = lv_text off = lv_from len = 1 ) CA `-._`.
      lv_from += 1.
    ENDWHILE.
    DATA(lv_to) = lv_len.
    WHILE lv_to > lv_from AND substring( val = lv_text off = lv_to - 1 len = 1 ) CA `-._`.
      lv_to -= 1.
    ENDWHILE.
    rv_slug = substring( val = lv_text off = lv_from len = lv_to - lv_from ).
  ENDMETHOD.


  METHOD branch_name.
    DATA(lv_slug) = slugify( iv_display_name ).
    IF strlen( lv_slug ) > 80.
      lv_slug = substring( val = lv_slug len = 80 ).
    ENDIF.
    IF lv_slug IS INITIAL.
      lv_slug = `migration`.
    ENDIF.
    DATA(lv_prefix) = slugify( iv_prefix ).
    rv_branch = COND #( WHEN lv_prefix IS NOT INITIAL THEN |{ lv_prefix }-{ lv_slug }| ELSE lv_slug ).
  ENDMETHOD.


  METHOD form_slug.
    DATA(lv_text) = to_lower( iv_form_name ).
    REPLACE ALL OCCURRENCES OF REGEX '[^a-z0-9]+' IN lv_text WITH '_'.
    DATA(lv_len) = strlen( lv_text ).
    DATA(lv_from) = 0.
    WHILE lv_from < lv_len AND substring( val = lv_text off = lv_from len = 1 ) = `_`.
      lv_from += 1.
    ENDWHILE.
    DATA(lv_to) = lv_len.
    WHILE lv_to > lv_from AND substring( val = lv_text off = lv_to - 1 len = 1 ) = `_`.
      lv_to -= 1.
    ENDWHILE.
    lv_text = substring( val = lv_text off = lv_from len = lv_to - lv_from ).
    IF strlen( lv_text ) > 60.
      lv_text = substring( val = lv_text len = 60 ).
    ENDIF.
    rv_slug = COND #( WHEN lv_text IS INITIAL THEN `form` ELSE lv_text ).
  ENDMETHOD.

ENDCLASS.
