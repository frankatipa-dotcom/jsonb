%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>  
#include <stdarg.h>

extern int yylex();
extern int yylineno;
void yyerror(const char *s);


typedef enum { 
    AST_STRING, 
    AST_NUMBER, 
    AST_BOOLEAN, 
    AST_NULL, 
    AST_OBJECT, 
    AST_ARRAY, 
    AST_SHELL_CMD,
    AST_IF,            // if block
    AST_FOR,           // for loop
    AST_BLOCK_LIST     // sequence of statements/nodes inside a block
} NodeType;


typedef struct ASTNode {
    NodeType type;
    char* string_val;      // literal or shell command content
    char* key;             // object key
    struct ASTNode* child; // first child (body of block, array items)
    struct ASTNode* next;  // next sibling
    // for if/for
    struct ASTNode* condition;   // expression that yields boolean (for IF)
    struct ASTNode* else_body;   // for IF-ELSE
    char* loop_var;               // variable name (FOR)
    struct ASTNode* iterable;     // expression that yields an array (FOR)
} ASTNode;

ASTNode *root_node = NULL;



// Quick helper function to allocate nodes
ASTNode* make_node(NodeType type) {
    ASTNode* node = (ASTNode*)malloc(sizeof(ASTNode));
    node->type = type;
    node->string_val = NULL;
    node->key = NULL;
    node->child = NULL;
    node->next = NULL;
    node->condition = NULL;
    node->else_body = NULL;
    node->loop_var = NULL;
    node->iterable = NULL;
    return node;
}


char *concat(const char *a, const char *b) {
    if (!a && !b) return strdup("");
    if (!a) return strdup(b);
    if (!b) return strdup(a);
    char *res = malloc(strlen(a) + strlen(b) + 1);
    strcpy(res, a);
    strcat(res, b);
    return res;
}




/* ---------- Context (variables) ---------- */
typedef struct Context {
    struct { char *key; char *value; } *vars;
    int size, cap;
} Context;

Context *context_new() {
    Context *ctx = calloc(1, sizeof(Context));
    ctx->cap = 8;
    ctx->vars = malloc(ctx->cap * sizeof(ctx->vars[0]));
    return ctx;
}

void context_set(Context *ctx, const char *key, const char *value) {
    for (int i = 0; i < ctx->size; i++) {
        if (strcmp(ctx->vars[i].key, key) == 0) {
            free(ctx->vars[i].value);
            ctx->vars[i].value = strdup(value);
            return;
        }
    }
    if (ctx->size >= ctx->cap) {
        ctx->cap *= 2;
        ctx->vars = realloc(ctx->vars, ctx->cap * sizeof(ctx->vars[0]));
    }
    ctx->vars[ctx->size].key = strdup(key);
    ctx->vars[ctx->size].value = strdup(value);
    ctx->size++;
}

char *context_get(Context *ctx, const char *key) {
    for (int i = 0; i < ctx->size; i++)
        if (strcmp(ctx->vars[i].key, key) == 0)
            return strdup(ctx->vars[i].value);
    return NULL;
}

void context_free(Context *ctx) {
    for (int i = 0; i < ctx->size; i++) {
        free(ctx->vars[i].key);
        free(ctx->vars[i].value);
    }
    free(ctx->vars);
    free(ctx);
}

/* ---------- Shell command execution ---------- */
char *exec_shell(const char *cmd) {
    char buf[256];
    char *result = strdup("");
    FILE *pipe = popen(cmd, "r");
    if (!pipe) return strdup("null");
    while (fgets(buf, sizeof(buf), pipe)) {
        char *old = result;
        result = concat(result, buf);
        free(old);
    }
    pclose(pipe);
    // trim trailing newline
    size_t len = strlen(result);
    if (len > 0 && result[len-1] == '\n') result[len-1] = '\0';
    return result;
}

/* ---------- String interpolation ---------- */
char *interpolate_string(const char *s, Context *ctx) {
    char *res = strdup("");
    const char *p = s;
    while (*p) {
        if (p[0] == '{' && p[1] == '{') {
            const char *end = strstr(p+2, "}}");
            if (!end) break;
            char *cmd = strndup(p+2, end - (p+2));
            char *out = exec_shell(cmd);
            char *old = res;
            res = concat(res, out);
            free(old);
            free(out);
            free(cmd);
            p = end + 2;
        } else {
            char *old = res;
            char tmp[2] = { *p, 0 };
            res = concat(res, tmp);
            free(old);
            p++;
        }
    }
    return res;
}

/* ---------- JSON array parsing (simple) ---------- */
// Parses a JSON array string like ["a","b",1] and calls fn for each element
void json_array_foreach(const char *json_arr, void (*fn)(const char *elem, void *user), void *user) {
    if (!json_arr || json_arr[0] != '[') return;
    const char *p = json_arr + 1;
    while (*p && *p != ']') {
        while (*p == ' ' || *p == '\t' || *p == '\n') p++;
        if (*p == '"') {
            p++;
            const char *start = p;
            while (*p && *p != '"') p++;
            char *elem = strndup(start, p - start);
            fn(elem, user);
            free(elem);
            if (*p == '"') p++;
        } else if (*p == '-' || (*p >= '0' && *p <= '9')) {
            const char *start = p;
            while (*p && ( (*p >= '0' && *p <= '9') || *p == '.' || *p == '-' || *p == 'e' || *p == 'E') ) p++;
            char *elem = strndup(start, p - start);
            fn(elem, user);
            free(elem);
        } else {
            // true/false/null – skip for brevity
            while (*p && *p != ',' && *p != ']') p++;
        }
        while (*p == ' ' || *p == '\t' || *p == '\n') p++;
        if (*p == ',') p++;
    }
}

/* ---------- Evaluation forward declarations ---------- */
char *eval_node(ASTNode *n, Context *ctx);
char *eval_object_body(ASTNode *items, Context *ctx);
char *eval_array_body(ASTNode *items, Context *ctx);

/* ---------- Eval implementations ---------- */
char *eval_node(ASTNode *n, Context *ctx) {
    if (!n) return strdup("");
    switch (n->type) {
        case AST_STRING: {
            char *interp = interpolate_string(n->string_val, ctx);
            char *quoted = malloc(strlen(interp) + 3);
            sprintf(quoted, "\"%s\"", interp);
            free(interp);
            return quoted;
        }
        case AST_NUMBER: {
            char *buf = malloc(strlen(n->string_val) + 1);
            strcpy(buf, n->string_val);
            return buf;
        }
        case AST_BOOLEAN: return strdup(n->string_val);
        case AST_NULL: return strdup("null");
        case AST_SHELL_CMD: {
            char *out = exec_shell(n->string_val);
            // try to parse as JSON, otherwise quote as string
            if (out[0] == '{' || out[0] == '[' || out[0] == '"' || 
                (out[0] >= '0' && out[0] <= '9') || !strcmp(out,"true") || !strcmp(out,"false") || !strcmp(out,"null"))
                return out;
            char *quoted = malloc(strlen(out) + 3);
            sprintf(quoted, "\"%s\"", out);
            free(out);
            return quoted;
        }
        case AST_OBJECT: {
            char *body = eval_object_body(n->child, ctx);
            char *res = concat("{", body);
            char *tmp = concat(res, "}");
            free(res); free(body);
            return tmp;
        }
        case AST_ARRAY: {
            char *body = eval_array_body(n->child, ctx);
            char *res = concat("[", body);
            char *tmp = concat(res, "]");
            free(res); free(body);
            return tmp;
        }
        case AST_IF: {
            char *cond_str = n->string_val; // "true"/"false"/identifier
            int cond = 0;
            if (strcmp(cond_str, "true") == 0) cond = 1;
            else if (strcmp(cond_str, "false") == 0) cond = 0;
            else {
                char *val = context_get(ctx, cond_str);
                if (val && strcmp(val, "true") == 0) cond = 1;
                free(val);
            }
            if (cond)
                return eval_object_body(n->child, ctx);
            else
                return eval_object_body(n->else_body, ctx);
        }
        case AST_FOR: {
            char *arr_str = context_get(ctx, n->string_val);
            if (!arr_str) return strdup("");
            struct PairCollector {
                Context *ctx;
                char *loop_var;
                ASTNode *body;
                char *result;
            } pc = {ctx, n->loop_var, n->child, strdup("")};
            void add_elem(const char *elem, void *user) {
                struct PairCollector *pc = user;
                context_set(pc->ctx, pc->loop_var, elem);
                char *body_res = eval_object_body(pc->body, pc->ctx);
                char *old = pc->result;
                pc->result = concat(pc->result, body_res);
                free(old);
                free(body_res);
            }
            json_array_foreach(arr_str, add_elem, &pc);
            free(arr_str);
            return pc.result;
        }
        default: return strdup("");
    }
}

char *eval_object_body(ASTNode *items, Context *ctx) {
    char *res = strdup("");
    ASTNode *item = items;
    while (item) {
        if (item->type == AST_IF || item->type == AST_FOR) {
            char *part = eval_node(item, ctx);
            char *old = res;
            res = concat(res, part);
            free(old);
            free(part);
        } else {
            // regular object item: key and value
            char *key_json = malloc(strlen(item->key) + 3);
            sprintf(key_json, "\"%s\"", item->key);
            char *val_json = eval_node(item, ctx);
            char *pair = concat(key_json, ":");
            char *pair2 = concat(pair, val_json);
            free(key_json); free(val_json); free(pair);
            char *old = res;
            if (res[0]) res = concat(res, ",");
            else res = concat(res, "");
            free(old);
            old = res;
            res = concat(res, pair2);
            free(old);
            free(pair2);
        }
        item = item->next;
    }
    return res;
}

char *eval_array_body(ASTNode *items, Context *ctx) {
    char *res = strdup("");
    ASTNode *item = items;
    while (item) {
        char *val = eval_node(item, ctx);
        char *old = res;
        if (res[0]) res = concat(res, ",");
        else res = concat(res, "");
        free(old);
        old = res;
        res = concat(res, val);
        free(old);
        free(val);
        item = item->next;
    }
    return res;
}


%}

%glr-parser   

%union {
    char* str;
    struct ASTNode* node;
}


/* Tell Bison that these grammar rules return an ASTNode pointer */
%type <node> document value json_string raw_expr object array 
%type <node> object_items object_item object_items_list 
%type <node> array_items array_item array_items_list

/* Tell Bison that these return strings */
%type <str> string_content shell_content_list block_expr


/* Tokens */
%token LBRACE RBRACE LBRACKET RBRACKET COLON COMMA
%token TRUE_TOK FALSE_TOK NULL_TOK
%token DOUBLE_QUOTE RAW_EXPR_START RAW_EXPR_END EXPR_START EXPR_END
%token BLOCK_START BLOCK_END
%token IF ELSE ENDIF FOR IN ENDFOR INCLUDE MACRO

%token <str> NUMBER STR_CHAR STRING_LITERAL SHELL_CONTENT IDENTIFIER

%start document

%%

document:
    value { 
        // We caught the root of the tree!
        $$ = $1; 
        root_node = $1;
    }
    ;

value:
    json_string    { $$ = $1; }
    | NUMBER       { $$ = make_node(AST_NUMBER); $$->string_val = strdup($1); }
    | TRUE_TOK     { $$ = make_node(AST_BOOLEAN); $$->string_val = strdup("true"); }
    | FALSE_TOK    { $$ = make_node(AST_BOOLEAN); $$->string_val = strdup("false"); }
    | NULL_TOK     { $$ = make_node(AST_NULL); $$->string_val = strdup("null"); }
    | raw_expr     { $$ = $1; }
    | object       { $$ = $1; }   /* Missing in your previous code! */
    | array        { $$ = $1; }   /* Missing in your previous code! */
    ;

/* ------ String with Interpolation ------ */
json_string:
    DOUBLE_QUOTE string_content DOUBLE_QUOTE {
        $$ = make_node(AST_STRING);
        $$->string_val = $2;
    }
    ;

string_content:
    /* empty */ { $$ = strdup(""); }
    | string_content STR_CHAR { $$ = concat($1, $2); }
    | string_content EXPR_START EXPR_END { $$ = $1; }
    | string_content EXPR_START shell_content_list EXPR_END {
        // Rebuild the literal string so the evaluator can parse it later
        char* tmp1 = concat($1, "{{");
        char* tmp2 = concat(tmp1, $3);
        $$ = concat(tmp2, "}}");
    }
    ;

shell_content_list:
    SHELL_CONTENT { $$ = strdup($1); }
    | shell_content_list SHELL_CONTENT { $$ = concat($1, $2); }
    ;

/* Shell Command Injection */
raw_expr:
    RAW_EXPR_START shell_content_list RAW_EXPR_END {
        $$ = make_node(AST_SHELL_CMD);
        $$->string_val = $2;
    }
    ;

/* ------ Objects ------ */
object:
    LBRACE object_items RBRACE {
        $$ = make_node(AST_OBJECT);
        $$->child = $2;
    }
    ;

object_items:
    /* empty */ { $$ = NULL; }
    | object_items_list { $$ = $1; }
    | object_items_list COMMA { $$ = $1; }
    ;

object_item: json_string COLON value {
    $$ = $3;
    $$->key = $1->string_val;
    free($1);
}
| BLOCK_START IF block_expr BLOCK_END object_items BLOCK_START ENDIF BLOCK_END {
    $$ = make_node(AST_IF);
    $$->string_val = $3;
    $$->child = $5;
}
| BLOCK_START IF block_expr BLOCK_END object_items BLOCK_START ELSE BLOCK_END object_items BLOCK_START ENDIF BLOCK_END {
    $$ = make_node(AST_IF);
    $$->string_val = $3;
    $$->child = $5;
    $$->else_body = $9;
}
| BLOCK_START FOR IDENTIFIER IN IDENTIFIER BLOCK_END object_items BLOCK_START ENDFOR BLOCK_END {
    $$ = make_node(AST_FOR);
    $$->loop_var = strdup($3);
    $$->string_val = strdup($5);
    $$->child = $7;
};


object_items_list:
    object_item {
        $$ = $1;
    }
    | object_items_list COMMA object_item {
        $$ = $1;
        ASTNode* curr = $$;
        while(curr && curr->next != NULL) curr = curr->next;
        if(curr) curr->next = $3;
        else $$ = $3;
    }
    ;

/* ------ Arrays ------ */
array:
    LBRACKET array_items RBRACKET {
        $$ = make_node(AST_ARRAY);
        $$->child = $2;
    }
    ;

array_items:
    /* empty */ { $$ = NULL; }
    | array_items_list { $$ = $1; }
    | array_items_list COMMA { $$ = $1; }
    ;

array_items_list:
    array_item { $$ = $1; }
    | array_items_list COMMA array_item {
        $$ = $1;
        ASTNode* curr = $$;
        while(curr && curr->next != NULL) curr = curr->next;
        if(curr) curr->next = $3;
        else $$ = $3;
    }
    | array_items_list array_item {
        $$ = $1;
        ASTNode* curr = $$;
        while(curr && curr->next != NULL) curr = curr->next;
        if(curr) curr->next = $2;
        else $$ = $2;
    }
    ;

array_item:
    /* Standard Element */
    value { $$ = $1; }
    
    /* Control Flow Blocks for Arrays - set to NULL until we map Block AST nodes */
    | BLOCK_START IF block_expr BLOCK_END array_items BLOCK_START ENDIF BLOCK_END { $$ = NULL; }
    | BLOCK_START IF block_expr BLOCK_END array_items BLOCK_START ELSE BLOCK_END array_items BLOCK_START ENDIF BLOCK_END { $$ = NULL; }
    | BLOCK_START FOR IDENTIFIER IN IDENTIFIER BLOCK_END array_items BLOCK_START ENDFOR BLOCK_END { $$ = NULL; }
    ;

/* ------ Block Expressions ------ */
block_expr:
    TRUE_TOK { $$ = strdup("true"); }
    | FALSE_TOK { $$ = strdup("false"); }
    | IDENTIFIER { $$ = strdup($1); }
    ;


%%

void yyerror(const char *s) {
    fprintf(stderr, "Parse Error at line %d: %s\n", yylineno, s);
}


// Executes a shell command and returns the output as a newly allocated string.
char* evaluate_shell_command(const char* cmd) {
    char buffer[256];
    size_t result_size = 1;
    char* result = malloc(result_size);
    result[0] = '\0';

    // Open a pipe to the shell command
    FILE *pipe = popen(cmd, "r");
    if (!pipe) {
        fprintf(stderr, "Failed to run command: %s\n", cmd);
        return strdup("null");
    }

    // Read the output block by block
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
        size_t len = strlen(buffer);
        result = realloc(result, result_size + len);
        strcat(result, buffer);
        result_size += len;
    }

    pclose(pipe);

    // Strip the trailing newline that echo/date usually adds
    if (result_size > 1 && result[result_size - 2] == '\n') {
        result[result_size - 2] = '\0';
    }

    return result;
}


int main(int argc, char **argv) {
    extern FILE *yyin;
    if (argc > 1) yyin = fopen(argv[1], "r");
    else yyin = stdin;
    if (yyparse() == 0 && root_node) {
        Context *ctx = context_new();
        char *out = eval_node(root_node, ctx);
        printf("%s\n", out);
        free(out);
        context_free(ctx);
    } else {
        fprintf(stderr, "Parse failed\n");
        return 1;
    }
    return 0;
}