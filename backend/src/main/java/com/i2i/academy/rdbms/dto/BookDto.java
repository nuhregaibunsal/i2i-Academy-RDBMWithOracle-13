package com.i2i.academy.rdbms.dto;

public record BookDto(
        long bookId,
        String title,
        String isbn,
        Integer publicationYear,
        String authorName,
        String publisherName
) {
}
