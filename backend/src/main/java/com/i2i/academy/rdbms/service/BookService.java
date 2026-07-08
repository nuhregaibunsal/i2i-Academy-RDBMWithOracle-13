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

    private static final String CALL_IMPORT = "{ call book_mgmt_pkg.prc_import_books(?, ?, ?) }";
    private static final String CALL_FETCH  = "{ call book_mgmt_pkg.prc_fetch_books(?) }";

    private final DataSource dataSource;

    public BookService(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    public ImportResponse importBooks(String rawPayload) throws SQLException {
        try (Connection conn = dataSource.getConnection();
             CallableStatement cs = conn.prepareCall(CALL_IMPORT)) {

            Clob payload = conn.createClob();
            payload.setString(1, rawPayload);

            cs.setClob(1, payload);
            cs.registerOutParameter(2, Types.NUMERIC);
            cs.registerOutParameter(3, Types.VARCHAR);
            cs.execute();

            int inserted = cs.getInt(2);
            String message = cs.getString(3);
            log.debug("Import completed: {} row(s)", inserted);
            return new ImportResponse(inserted, message);

        } catch (SQLException ex) {
            throw translate(ex);
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
                            rs.getString("isbn"),
                            (Integer) rs.getObject("publication_year"),
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
