" RangeMacro.vim: Execute macro repeatedly until the end of a range is reached. 
"
" DEPENDENCIES:
"   - ingomarks.vim autoload script. 
"
" Copyright: (C) 2010 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'. 
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" REVISION	DATE		REMARKS 
"   1.00.005	05-Oct-2010	Factored out checking for invalid registers and
"				print error message now, as the :@ command does. 
"	004	04-Oct-2010	ENH: Supporting block selection mode. 
"	003	03-Oct-2010	Handling visual mode selections, too. 
"	002	02-Oct-2010	Moved from incubator to proper autoload/plugin
"				scripts. 
"	001	02-Oct-2010	file creation
let s:save_cpo = &cpo
set cpo&vim

let s:recurseMapping = "\<Plug>RangeMacroRecurse"
function! RangeMacro#SetRegister( register )
    let s:register = a:register
endfunction

function! s:CheckRegister( register )
    if stridx(g:RangeMacro_Registers, a:register) == -1
	let v:errmsg = printf("E354: Invalid register name: '%s'", a:register)
	echohl ErrorMsg
	echomsg v:errmsg
	echohl None

	return 0
    else
	return 1
    endif
endfunction
function! RangeMacro#Operator( type )
    unlet! s:selectionMode

"****D echomsg '****' string(getpos('.')) string(getpos("'[")) string(getpos("']"))
    if ! s:CheckRegister(s:register) | return | endif

    call RangeMacro#Start(getpos("'["), getpos("']"))
endfunction
function! RangeMacro#Selection( register )
    if ! s:CheckRegister(a:register) | return | endif
    let s:register = a:register
    let s:selectionMode = visualmode()

    call RangeMacro#Start(getpos("'<"), getpos("'>"))
endfunction
function! RangeMacro#Command( startLine, endLine, register )
    if ! s:CheckRegister(a:register) | return | endif
    let s:register = (empty(a:register) ? '"' : a:register)
    unlet! s:selectionMode

    " Position cursor at the beginning of the range, first column. 
    execute 'keepjumps normal!' a:startLine . 'G0'
    call RangeMacro#Start( [0, a:startLine, 1, 0], [0, a:endLine, strlen(getline(a:endLine)), 0])
endfunction
function! s:GetRangeMarks()
    return [ "'" . keys(s:marksRecord)[0], "'" . keys(s:marksRecord)[1]]
endfunction

function! RangeMacro#Start( startPos, endPos )
"****D echomsg '****' string(a:startPos) string(a:endPos)
    " The macro may change the number of lines in the range. Thus, we use two
    " marks instead of simply storing the positions of the range edges. Because
    " Vim adapts the mark positions when lines are inserted / removed, the macro
    " will operate on the original range, as intended. 
    let s:marksRecord = ingomarks#ReserveMarks(2)
    let [l:startMark, l:endMark] = s:GetRangeMarks()
    call setpos(l:startMark, a:startPos)
    call setpos(l:endMark, a:endPos)
    
    " Append recursive macro invocation if not yet there. 
    execute 'let l:macro = @' . s:register
    " Note: Cannot use "\<Plug>" in comparison; it will never match. 
    "if l:macro !~# s:recurseMapping . '$'
    if strpart(l:macro, strlen(l:macro) - strlen(s:recurseMapping)) !=# s:recurseMapping
	execute 'let @' . s:register . ' .= ' . string(s:recurseMapping)
    endif

    " Install autocmd to eventually clean up the modified macro in case the
    " macro errors out before the regular end of the macro execution outside the
    " macro range is reached. 
    augroup RangeMacroCleanup
	autocmd!
	autocmd CursorHold * call s:Cleanup() | autocmd! RangeMacroCleanup
    augroup END

    " Start off the iteration by invoking the (augmented) macro once. 
    try
	execute 'normal! @' . s:register
    catch /^Vim\%((\a\+)\)\=:E/
	" v:exception contains what is normally in v:errmsg, but with extra
	" exception source info prepended, which we cut away. 
	let v:errmsg = substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', '')
	echohl ErrorMsg
	echomsg v:errmsg
	echohl None
    endtry
endfunction

function! s:Cleanup()
    unlet! s:selectionMode

    if exists('s:register')
	" Restore used marks to previous, recorded state. 
	call ingomarks#UnreserveMarks(s:marksRecord)
	unlet s:marksRecord

	" Clean up the recursive invocation appended to the macro. 
	execute 'let l:macro = @' . s:register
	if strpart(l:macro, strlen(l:macro) - strlen(s:recurseMapping)) ==# s:recurseMapping
	    execute 'let  @' . s:register . ' = strpart(l:macro, 0, strlen(l:macro) - strlen(s:recurseMapping))'
	endif

	" Invalidate the saved macro register. 
	unlet s:register
    endif
endfunction
function! RangeMacro#Recurse( mode )
    let [l:startPos, l:endPos] = map(s:GetRangeMarks(), 'getpos(v:val)')
    let [l:startLine, l:startCol] = [l:startPos[1], l:startPos[2]]
    let [l:endLine, l:endCol] = [l:endPos[1], l:endPos[2]]

    " In block selection mode, the start and end columns must be checked on
    " every line, not just at the start and end of the range. 
    let l:isBlockSelection = (exists('s:selectionMode') && s:selectionMode ==# "\<C-v>")

    if
    \	l:startPos == [0, 0, 0, 0] ||
    \	l:endPos == [0, 0, 0, 0] ||
    \   line('.') < l:startLine ||
    \	((l:isBlockSelection || line('.') == l:startLine) && col('.') < l:startCol) ||
    \   line('.') > l:endLine ||
    \	((l:isBlockSelection || line('.') == l:endLine) && col('.') > l:endCol)
	" Went outside of range. 
	call s:Cleanup()

	" Stop recursion. 
	" Note: An empty command will beep in normal mode; use another no-op
	" command. 
	"return ''
	return (a:mode ==# 'n' ? ":\<Esc>" : '')
    else
"****D redraw | sleep 2
	" Still inside the range. Recurse. 
	return (a:mode ==# 'n' ? '' : "\<Esc>") . '@' . s:register
    endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
" vim: set sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
