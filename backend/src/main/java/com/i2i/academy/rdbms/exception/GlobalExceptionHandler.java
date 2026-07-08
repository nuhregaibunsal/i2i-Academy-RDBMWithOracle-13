package com.i2i.academy.rdbms.exception;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.sql.SQLException;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(PlSqlBusinessException.class)
    public ResponseEntity<ApiError> handleBusiness(PlSqlBusinessException ex) {
        log.warn("Business rule rejected request (ORA{}): {}", ex.getOracleErrorCode(), ex.getMessage());
        return ResponseEntity
                .status(HttpStatus.BAD_REQUEST)
                .body(ApiError.of(400, "Bad Request", ex.getMessage()));
    }

    @ExceptionHandler(SQLException.class)
    public ResponseEntity<ApiError> handleSql(SQLException ex) {
        log.error("Unhandled database failure", ex);
        return ResponseEntity
                .status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiError.of(500, "Internal Server Error",
                        "A database error occurred while processing the request."));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> handleGeneric(Exception ex) {
        log.error("Unexpected server failure", ex);
        return ResponseEntity
                .status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiError.of(500, "Internal Server Error", "An unexpected error occurred."));
    }
}
