CREATE OR REPLACE PACKAGE BODY book_mgmt_pkg AS

  c_field_count CONSTANT PLS_INTEGER := 8;

  FUNCTION resolve_publisher (
    p_name    IN publishers.name%TYPE,
    p_country IN publishers.country%TYPE
  ) RETURN publishers.publisher_id%TYPE IS
    v_id publishers.publisher_id%TYPE;
  BEGIN
    SELECT publisher_id INTO v_id FROM publishers WHERE name = p_name;
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      INSERT INTO publishers (name, country)
      VALUES (p_name, p_country)
      RETURNING publisher_id INTO v_id;
      RETURN v_id;
  END resolve_publisher;

  FUNCTION resolve_author (
    p_first IN authors.first_name%TYPE,
    p_last  IN authors.last_name%TYPE,
    p_birth IN authors.birth_year%TYPE
  ) RETURN authors.author_id%TYPE IS
    v_id authors.author_id%TYPE;
  BEGIN
    SELECT author_id INTO v_id
      FROM authors
     WHERE first_name = p_first AND last_name = p_last;
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      INSERT INTO authors (first_name, last_name, birth_year)
      VALUES (p_first, p_last, p_birth)
      RETURNING author_id INTO v_id;
      RETURN v_id;
  END resolve_author;

  FUNCTION fn_raw_to_json (p_raw IN CLOB) RETURN CLOB IS
    v_json CLOB;
  BEGIN
    IF p_raw IS NULL OR DBMS_LOB.getlength(p_raw) = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_empty_input,
        'Import payload is empty; nothing to transform.');
    END IF;

    WITH records AS (
      SELECT TRIM(REGEXP_SUBSTR(p_raw, '[^~]+', 1, LEVEL)) AS rec,
             LEVEL AS rn
        FROM dual
     CONNECT BY REGEXP_SUBSTR(p_raw, '[^~]+', 1, LEVEL) IS NOT NULL
    ),
    parsed AS (
      SELECT rn,
             TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 1)) AS title,
             TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 2)) AS isbn,
             TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 3)) AS pub_year,
             TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 4)) AS author_first,
             TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 5)) AS author_last,
             TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 6)) AS author_birth,
             TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 7)) AS publisher_name,
             TRIM(REGEXP_SUBSTR(rec, '[^|]+', 1, 8)) AS publisher_country,
             REGEXP_COUNT(rec, '\|') + 1              AS field_count
        FROM records
    )
    SELECT JSON_ARRAYAGG(
             JSON_OBJECT(
               'title'            VALUE title,
               'isbn'             VALUE isbn,
               'pubYear'          VALUE pub_year,
               'authorFirst'      VALUE author_first,
               'authorLast'       VALUE author_last,
               'authorBirth'      VALUE author_birth,
               'publisherName'    VALUE publisher_name,
               'publisherCountry' VALUE publisher_country,
               'fieldCount'       VALUE field_count
             )
             ORDER BY rn RETURNING CLOB
           )
      INTO v_json
      FROM parsed;

    RETURN v_json;
  END fn_raw_to_json;

  PROCEDURE prc_import_books (
    p_raw      IN  CLOB,
    p_inserted OUT NUMBER,
    p_message  OUT VARCHAR2
  ) IS
    v_json         CLOB;
    v_count        PLS_INTEGER := 0;
    v_author_id    authors.author_id%TYPE;
    v_publisher_id publishers.publisher_id%TYPE;
  BEGIN
    p_inserted := 0;

    v_json := fn_raw_to_json(p_raw);

    FOR rec IN (
      SELECT jt.title, jt.isbn, jt.pub_year, jt.author_first, jt.author_last,
             jt.author_birth, jt.publisher_name, jt.publisher_country,
             jt.field_count
        FROM JSON_TABLE(
               v_json, '$[*]'
               COLUMNS (
                 title             VARCHAR2(300) PATH '$.title',
                 isbn              VARCHAR2(20)  PATH '$.isbn',
                 pub_year          NUMBER        PATH '$.pubYear',
                 author_first      VARCHAR2(100) PATH '$.authorFirst',
                 author_last       VARCHAR2(100) PATH '$.authorLast',
                 author_birth      NUMBER        PATH '$.authorBirth',
                 publisher_name    VARCHAR2(200) PATH '$.publisherName',
                 publisher_country VARCHAR2(100) PATH '$.publisherCountry',
                 field_count       NUMBER        PATH '$.fieldCount'
               )
             ) jt
    ) LOOP
      IF rec.field_count <> c_field_count
         OR rec.title IS NULL OR rec.isbn IS NULL
         OR rec.author_first IS NULL OR rec.author_last IS NULL
         OR rec.publisher_name IS NULL THEN
        RAISE_APPLICATION_ERROR(c_err_bad_format,
          'Malformed record #' || (v_count + 1) ||
          ': expected ' || c_field_count || ' non-empty fields.');
      END IF;

      v_publisher_id := resolve_publisher(rec.publisher_name, rec.publisher_country);
      v_author_id    := resolve_author(rec.author_first, rec.author_last, rec.author_birth);

      INSERT INTO books (title, isbn, publication_year, author_id, publisher_id)
      VALUES (rec.title, rec.isbn, rec.pub_year, v_author_id, v_publisher_id);

      v_count := v_count + 1;
    END LOOP;

    COMMIT;

    p_inserted := v_count;
    p_message  := 'Import successful: ' || v_count || ' book(s) persisted.';

  EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
      ROLLBACK;
      RAISE_APPLICATION_ERROR(c_err_duplicate_isbn,
        'Duplicate ISBN detected; the entire batch was rolled back.');

    WHEN OTHERS THEN
      ROLLBACK;
      IF SQLCODE BETWEEN -20999 AND -20000 THEN
        RAISE;
      ELSE
        RAISE_APPLICATION_ERROR(c_err_unexpected,
          'Unexpected import failure: ' || SQLERRM);
      END IF;
  END prc_import_books;

  PROCEDURE prc_fetch_books (p_result OUT SYS_REFCURSOR) IS
    CURSOR c_books IS
      SELECT b.book_id,
             b.title,
             b.isbn,
             b.publication_year,
             a.first_name || ' ' || a.last_name AS author_name,
             p.name                              AS publisher_name
        FROM books b
        JOIN authors    a ON a.author_id    = b.author_id
        JOIN publishers p ON p.publisher_id = b.publisher_id
       ORDER BY b.title;

    v_row  c_books%ROWTYPE;
    v_data book_detail_tab := book_detail_tab();
  BEGIN
    OPEN c_books;
    LOOP
      FETCH c_books INTO v_row;
      EXIT WHEN c_books%NOTFOUND;
      v_data.EXTEND;
      v_data(v_data.LAST) := book_detail_obj(
        v_row.book_id, v_row.title, v_row.isbn,
        v_row.publication_year, v_row.author_name, v_row.publisher_name
      );
    END LOOP;
    CLOSE c_books;

    OPEN p_result FOR SELECT * FROM TABLE(v_data);
  END prc_fetch_books;

END book_mgmt_pkg;
/

PROMPT Package body compiled.
SHOW ERRORS
