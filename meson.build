
project('jsonb', 'c',
  version : '1.0',
  default_options : ['warning_level=2', 'c_std=gnu11'])  

# Find the installed binaries
flex = find_program('flex', required: true)
bison = find_program('bison', required: true)

# 1. Generate Parser (Bison)
bison_gen = custom_target(
  'bison_gen',
  input : 'src/jsonb.y',
  output : ['jsonb.tab.c', 'jsonb.tab.h'],
  command : [bison, '-d', '@INPUT@', '-o', '@OUTPUT0@']
)

# 2. Generate Lexer (Flex)
flex_gen = custom_target(
  'flex_gen',
  input : 'src/jsonb.l',
  output : 'lex.yy.c',
  command : [flex, '-o', '@OUTPUT@', '@INPUT@']
)

# 3. Build the Executable
executable(
  'jsonb',
  sources : [flex_gen, bison_gen]
  install : true
)