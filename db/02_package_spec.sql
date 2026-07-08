CREATE OR REPLACE PACKAGE book_mgmt_pkg AS

  c_err_empty_input     CONSTANT PLS_INTEGER := -20001;
  c_err_bad_format      CONSTANT PLS_INTEGER := -20002;
  c_err_duplicate_isbn  CONSTANT PLS_INTEGER := -20003;
  c_err_unexpected      CONSTANT PLS_INTEGER := -20099;

  FUNCTION fn_raw_to_json (p_raw IN CLOB) RETURN CLOB;

  PROCEDURE prc_import_books (
    p_raw        IN  CLOB,
    p_inserted   OUT NUMBER,
    p_message    OUT VARCHAR2
  );

  PROCEDURE prc_fetch_books (p_result OUT SYS_REFCURSOR);

END book_mgmt_pkg;
/

PROMPT Package specification compiled.
