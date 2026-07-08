package com.i2i.academy.rdbms.exception;

public class PlSqlBusinessException extends RuntimeException {

    private final int oracleErrorCode;

    public PlSqlBusinessException(int oracleErrorCode, String message) {
        super(message);
        this.oracleErrorCode = oracleErrorCode;
    }

    public int getOracleErrorCode() {
        return oracleErrorCode;
    }
}
