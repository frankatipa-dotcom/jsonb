%{
/* Define GNU/POSIX extensions BEFORE any headers are included */
#define _GNU_SOURCE

#include <stdio.h>
#include <string.h>
#include "jsonb.tab.h"

void yyerror(const char *s);


%}

/* Enable state stack, disable unused functions to clean up warnings */
%option noyywrap yylineno stack noinput nounput noyy_top_state

/* Lexer States */
%x IN_STRING IN_RAW_EXPR IN_EXPR IN_BLOCK
%x IN_SHELL
%%

<INITIAL>{
    "{"                     { return LBRACE; }
    "}"                     { return RBRACE; }
    "["                     { return LBRACKET; }
    "]"                     { return RBRACKET; }
    ":"                     { return COLON; }
    ","                     { return COMMA; }
    
    "true"                  { return TRUE_TOK; }
    "false"                 { return FALSE_TOK; }
    "null"                  { return NULL_TOK; }
    
    /* Enter string state */
    \"                      { yy_push_state(IN_STRING); return DOUBLE_QUOTE; }
    
    /* Enter raw expression state */
    "{{{"                   { yy_push_state(IN_RAW_EXPR); return RAW_EXPR_START; }
    
    /* Enter block state */
    "{%"                    { yy_push_state(IN_BLOCK); return BLOCK_START; }
    
    /* Standard JSON Numbers */
    -?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)? { yylval.str = strdup(yytext); return NUMBER; }
    
    [ \t\n\r]+              { /* Skip whitespace */ }
    .                       { return yytext[0]; }
}

<IN_STRING>{
    \"                      { yy_pop_state(); return DOUBLE_QUOTE; }
    
    /* String interpolation */
    "{{"                    { yy_push_state(IN_EXPR); return EXPR_START; }
    
    /* Escaped characters */
    \\["\\/bfnrt]           { yylval.str = strdup(yytext); return STR_CHAR; }
    \\u[0-9a-fA-F]{4}       { yylval.str = strdup(yytext); return STR_CHAR; }
    
    /* Normal string contents (allow literal newlines based on multiline test case) */
    [^\"{\\]+               { yylval.str = strdup(yytext); return STR_CHAR; }
    
    /* Catch standalone braces not part of {{ */
    "{"                     { yylval.str = strdup(yytext); return STR_CHAR; }
}

<IN_RAW_EXPR>{
    "}}?"                   { /* do nothing */ }
    "}}}"                   { yy_pop_state(); return RAW_EXPR_END; }
    [^}]+                   { yylval.str = strdup(yytext); return SHELL_CONTENT; }
    "}"                     { yylval.str = strdup(yytext); return SHELL_CONTENT; }
}

<IN_EXPR>{
    "}}"                    { yy_pop_state(); return EXPR_END; }
    [^}\n]+                 { yylval.str = strdup(yytext); return SHELL_CONTENT; }
    "}"                     { yylval.str = strdup(yytext); return SHELL_CONTENT; }
}

<IN_BLOCK>{
    "%}"                    { yy_pop_state(); return BLOCK_END; }
    
    "if"                    { return IF; }
    "else"                  { return ELSE; }
    "endif"                 { return ENDIF; }
    "for"                   { return FOR; }
    "in"                    { return IN; }
    "endfor"                { return ENDFOR; }
    "include"               { return INCLUDE; }
    "macro"                 { return MACRO; }
    
    "true"                  { return TRUE_TOK; }
    "false"                 { return FALSE_TOK; }
    
    /* Single or double quoted strings inside blocks */
    \"([^\"\\]|\\.)*\" |
    '([^'\\]|\\.)*'         { yylval.str = strdup(yytext); return STRING_LITERAL; }
    
    [a-zA-Z_][a-zA-Z0-9_]* { yylval.str = strdup(yytext); return IDENTIFIER; }
    
    [ \t\n\r]+              { /* Skip whitespace */ }
    .                       { return yytext[0]; }
}

%%