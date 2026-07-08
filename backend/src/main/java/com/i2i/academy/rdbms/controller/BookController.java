package com.i2i.academy.rdbms.controller;

import com.i2i.academy.rdbms.dto.BookDto;
import com.i2i.academy.rdbms.dto.ImportResponse;
import com.i2i.academy.rdbms.service.BookService;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.sql.SQLException;
import java.util.List;

@RestController
@RequestMapping("/api/books")
public class BookController {

    private final BookService bookService;

    public BookController(BookService bookService) {
        this.bookService = bookService;
    }

    @PostMapping(value = "/import", consumes = MediaType.TEXT_PLAIN_VALUE)
    public ResponseEntity<ImportResponse> importBooks(@RequestBody String rawPayload) throws SQLException {
        ImportResponse response = bookService.importBooks(rawPayload);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping(produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<List<BookDto>> listBooks() throws SQLException {
        return ResponseEntity.ok(bookService.fetchBooks());
    }
}
