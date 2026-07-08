package com.i2i.academy.rdbms.service;

import com.i2i.academy.rdbms.dto.BookDto;
import com.i2i.academy.rdbms.dto.ImportResponse;
import com.i2i.academy.rdbms.exception.PlSqlBusinessException;
import oracle.jdbc.OracleTypes;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import javax.sql.DataSource;
import java.sql.CallableStatement;
import java.sql.Clob;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

@Service
public class BookService {

    private static final Logger log = LoggerFactory.getLogger(BookService.class);

    private static final int ORA_USER_ERROR_MAX = 20000;
    private static final int ORA_USER_ERROR_MIN = 20999;

    private static final String CALL_TO_XML  = "{ ? = call book_operations.fn_to_xml(?) }";
    private static final String CALL_TO_JSON = "{ ? = call book_operations.fn_to_json(?) }";
    private static final String CALL_IMPORT  = "{ call book_operations.prc_import_books(?, ?, ?, ?) }";
    private static final String CALL_FETCH   = "{ call book_operations.prc_fetch_books(?) }";

    private final DataSource dataSource;

    public BookService(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    public ImportResponse importBooks(String rawPayload) throws SQLException {
        try (Connection conn = dataSource.getConnection()) {
            String xml = transform(conn, CALL_TO_XML, rawPayload);
            String json = transform(conn, CALL_TO_JSON, rawPayload);
            return persist(conn, xml, json);
        } catch (SQLException ex) {
            throw translate(ex);
        }
    }

    private String transform(Connection conn, String call, String rawPayload) throws SQLException {
        try (CallableStatement cs = conn.prepareCall(call)) {
            Clob payload = conn.createClob();
            payload.setString(1, rawPayload);
            cs.registerOutParameter(1, Types.CLOB);
            cs.setClob(2, payload);
            cs.execute();
            return cs.getString(1);
        }
    }

    private ImportResponse persist(Connection conn, String xml, String json) throws SQLException {
        try (CallableStatement cs = conn.prepareCall(CALL_IMPORT)) {
            Clob xmlClob = conn.createClob();
            xmlClob.setString(1, xml);
            Clob jsonClob = conn.createClob();
            jsonClob.setString(1, json);

            cs.setClob(1, xmlClob);
            cs.setClob(2, jsonClob);
            cs.registerOutParameter(3, Types.NUMERIC);
            cs.registerOutParameter(4, Types.VARCHAR);
            cs.execute();

            int inserted = cs.getInt(3);
            String message = cs.getString(4);
            log.debug("Import completed: {} row(s)", inserted);
            return new ImportResponse(inserted, message);
        }
    }

    public List<BookDto> fetchBooks() throws SQLException {
        try (Connection conn = dataSource.getConnection();
             CallableStatement cs = conn.prepareCall(CALL_FETCH)) {

            cs.registerOutParameter(1, OracleTypes.CURSOR);
            cs.execute();

            List<BookDto> books = new ArrayList<>();
            try (ResultSet rs = (ResultSet) cs.getObject(1)) {
                while (rs.next()) {
                    books.add(new BookDto(
                            rs.getLong("book_id"),
                            rs.getString("title"),
                            rs.getString("author_name"),
                            rs.getString("publisher_name")
                    ));
                }
            }
            log.debug("Fetched {} book(s)", books.size());
            return books;
        }
    }

    private RuntimeException translate(SQLException ex) throws SQLException {
        int code = ex.getErrorCode();
        if (code >= ORA_USER_ERROR_MAX && code <= ORA_USER_ERROR_MIN) {
            return new PlSqlBusinessException(code, cleanMessage(ex.getMessage()));
        }
        throw ex;
    }

    private String cleanMessage(String raw) {
        if (raw == null) {
            return "Import rejected by the database engine.";
        }
        int cut = raw.indexOf("ORA-06512");
        String head = (cut > 0 ? raw.substring(0, cut) : raw).trim();
        return head.replaceFirst("^ORA-\\d+:\\s*", "");
    }
}
