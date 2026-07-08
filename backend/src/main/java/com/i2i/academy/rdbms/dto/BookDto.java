package com.i2i.academy.rdbms.dto;

public record BookDto(
        long id,
        String title,
        String author,
        String publisher
) {
}
