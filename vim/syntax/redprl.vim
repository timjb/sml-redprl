" vim-RedPRL syntax
" Language:     RedPRL
" Author:       Carlo Angiuli
" Last Change:  2018 February 7

if exists("b:current_syntax")
  finish
endif

setlocal iskeyword+=-
setlocal iskeyword+=/

syn keyword redDecl define print theorem tactic quit extract
syn keyword redSort dim hyp exp lvl tac jdg knd
syn match   redHole '?\(\a\|\d\|\'\|\/\|\-\)*'
syn match   redMeta '#'

syn keyword redExpr ax fcom bool tt ff if nat
syn keyword redExpr zero succ nat-rec int pos negsucc int-rec void S1 base loop
syn keyword redExpr S1-rec lam record tuple path line pushout left right glue
syn keyword redExpr pushout-rec coeq cecod cedom coeq-rec mem ni box cap V VV WU
syn keyword redExpr Vin Vproj U abs hcom com ghcom gcom coe lmax omega
syn match   redExpr '[$*!@=+]\|->\|\~>\|<\~'

syn keyword redTac auto auto-step case cut-lemma elim else exact goal
syn keyword redTac hyp id lemma let claim match of print trace progress
syn keyword redTac query reduce refine repeat rewrite symmetry
syn keyword redTac then unfold use with without fail inversion concl assumption
syn match   redTac '[;`]'

syn keyword redSeq at by in true type synth discrete kan pre

syn region  redComm start="//" end="$"
syn region  redBlockComm start="/\*" end="\*/" contains=redBlockComm

syn match   redMesg '\[\(Info\|Output\|Warning\|Error\)\]'
syn keyword redMesg Trace

syn match   redAnon '_\d\+'
syn match   redAnon '_\d\+\/\(\a\|\d\|\'\|\/\|\-\)\+'

hi def link redDecl Structure
hi def link redSort Identifier
hi def link redHole Error
hi def link redMeta Identifier
hi def link redExpr Identifier
hi def link redTac  Statement
hi def link redSeq  Normal
hi def link redComm Comment
hi def link redBlockComm Comment
hi def link redMesg Structure
hi def link redAnon NonText

let b:current_syntax = "redprl"
