# Всегда собирать report.tex
@default_files = ('report.tex');

# XeLaTeX
$pdf_mode = 5;

# report.pdf в корне, служебные файлы в .build/
$out_dir = '.';
$aux_dir = '.build';

# BibTeX и ugost2008-utf8.bst из корня
$bibtex_use = 2;
ensure_path('BSTINPUTS', './/');
ensure_path('BIBINPUTS', './/');

set_tex_cmds('-synctex=1 -interaction=nonstopmode -file-line-error %O %S');