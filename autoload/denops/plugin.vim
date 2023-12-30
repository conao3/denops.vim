let s:loaded_plugins = {}
let s:load_callbacks = {}

function! denops#plugin#is_loaded(plugin) abort
  return has_key(s:loaded_plugins, a:plugin)
endfunction

function! denops#plugin#wait(plugin, ...) abort
  let l:options = extend({
        \ 'interval': g:denops#plugin#wait_interval,
        \ 'timeout': g:denops#plugin#wait_timeout,
        \ 'silent': 0,
        \}, a:0 ? a:1 : {},
        \)
  if denops#server#status() ==# 'stopped'
    if !l:options.silent
      call denops#_internal#echo#error(printf(
            \ 'Failed to wait for "%s" to start. Denops server itself is not started.',
            \ a:plugin,
            \))
    endif
    return -2
  endif
  if has_key(s:loaded_plugins, a:plugin)
    return s:loaded_plugins[a:plugin]
  endif
  let l:ret = denops#_internal#wait#for(
        \ l:options.timeout,
        \ { -> has_key(s:loaded_plugins, a:plugin) },
        \ l:options.interval,
        \)
  if l:ret is# -1
    if !l:options.silent
      call denops#_internal#echo#error(printf(
            \ 'Failed to wait for "%s" to start. It took more than %d milliseconds and timed out.',
            \ a:plugin,
            \ l:options.timeout,
            \))
    endif
    return -1
  endif
endfunction

function! denops#plugin#wait_async(plugin, callback) abort
  if has_key(s:loaded_plugins, a:plugin)
    if s:loaded_plugins[a:plugin] isnot# 0
      return
    endif
    call a:callback()
    return
  endif
  let l:callbacks = get(s:load_callbacks, a:plugin, [])
  call add(l:callbacks, a:callback)
  let s:load_callbacks[a:plugin] = l:callbacks
endfunction

function! denops#plugin#register(plugin, ...) abort
  if a:0 is# 0
    " denops#plugin#register({plugin}) is deprecated.
    call denops#_internal#echo#deprecate(
          \ 'The {script} argument of `denops#plugin#register` will be non optional. Please specify the script path of the plugin.',
          \)
    return denops#plugin#register(a:plugin, s:find_plugin(a:plugin))
  elseif a:0 is# 1 && type(a:1) is# v:t_dict
    " denops#plugin#register({plugin}, {option}) is deprecated.
    call denops#_internal#echo#deprecate(
          \ 'The {option} argument of `denops#plugin#register` is removed.',
          \)
    return denops#plugin#register(a:plugin, s:find_plugin(a:plugin))
  elseif a:0 >= 2
    " denops#plugin#register({plugin}, {script}, {option}) is deprecated.
    call denops#_internal#echo#deprecate(
          \ 'The {option} argument of `denops#plugin#register` is removed.',
          \)
    return denops#plugin#register(a:plugin, a:1)
  endif

  let l:script = a:1
  return s:register(a:plugin, l:script)
endfunction

function! denops#plugin#reload(plugin, ...) abort
  if a:0 >= 1
    " denops#plugin#reload({plugin}, {option}) is deprecated.
    call denops#_internal#echo#deprecate(
          \ 'The {option} argument of `denops#plugin#reload` is removed.',
          \)
  endif
  let l:args = [a:plugin]
  call denops#_internal#echo#debug(printf('reload plugin: %s', l:args))
  return denops#server#notify('invoke', ['reload', l:args])
endfunction

function! denops#plugin#discover(...) abort
  if a:0 >= 1
    " denops#plugin#discover({option}) is deprecated.
    call denops#_internal#echo#deprecate(
          \ 'The {option} argument of `denops#plugin#discover` is removed.',
          \)
  endif
  let l:plugins = {}
  call s:gather_plugins(l:plugins)
  call denops#_internal#echo#debug(printf('%d plugins are discovered', len(l:plugins)))
  for [l:plugin, l:script] in items(l:plugins)
    call s:register(l:plugin, l:script)
  endfor
endfunction

function! denops#plugin#check_type(...) abort
  if !a:0
    let l:plugins = {}
    call s:gather_plugins(l:plugins)
  endif
  let l:args = [g:denops#deno, 'check']
  let l:args += a:0 ? [s:find_plugin(a:1)] : values(l:plugins)
  let l:job = denops#_internal#job#start(l:args, {
        \ 'env': {
        \   'NO_COLOR': 1,
        \   'DENO_NO_PROMPT': 1,
        \ },
        \ 'on_stderr': { _job, data, _event -> denops#_internal#echo#info(data) },
        \ 'on_exit': { _job, status, _event -> status 
        \   ? denops#_internal#echo#error('Type check failed:', status)
        \   : denops#_internal#echo#info('Type check succeeded')
        \ },
        \ })
endfunction

function! s:gather_plugins(plugins) abort
  for l:script in globpath(&runtimepath, denops#_internal#path#join(['denops', '*', 'main.ts']), 1, 1, 1)
    let l:plugin = fnamemodify(l:script, ':h:t')
    if l:plugin[:0] ==# '@' || has_key(a:plugins, l:plugin)
      continue
    endif
    call extend(a:plugins, { l:plugin : l:script })
  endfor
endfunction

function! s:register(plugin, script) abort
  execute printf('doautocmd <nomodeline> User DenopsSystemPluginRegister:%s', a:plugin)
  let l:script = denops#_internal#path#norm(a:script)
  let l:args = [a:plugin, l:script]
  call denops#_internal#echo#debug(printf('register plugin: %s', l:args))
  call denops#server#notify('invoke', ['register', l:args])
endfunction

function! s:find_plugin(plugin) abort
  for l:script in globpath(&runtimepath, denops#_internal#path#join(['denops', a:plugin, 'main.ts']), 1, 1, 1)
    let l:plugin = fnamemodify(l:script, ':h:t')
    if l:plugin[:0] ==# '@' || !filereadable(l:script)
      continue
    endif
    return l:script
  endfor
  throw printf('No denops plugin for "%s" exists', a:plugin)
endfunction

function! s:DenopsSystemPluginRegister() abort
  let l:plugin = matchstr(expand('<amatch>'), 'DenopsSystemPluginRegister:\zs.*')
  execute printf('doautocmd <nomodeline> User DenopsPluginRegister:%s', l:plugin)
endfunction

function! s:DenopsSystemPluginPre() abort
  let l:plugin = matchstr(expand('<amatch>'), 'DenopsSystemPluginPre:\zs.*')
  execute printf('doautocmd <nomodeline> User DenopsPluginPre:%s', l:plugin)
endfunction

function! s:DenopsSystemPluginPost() abort
  let l:plugin = matchstr(expand('<amatch>'), 'DenopsSystemPluginPost:\zs.*')
  let s:loaded_plugins[l:plugin] = 0
  if has_key(s:load_callbacks, l:plugin)
    for l:Callback in remove(s:load_callbacks, l:plugin)
      call l:Callback()
    endfor
  endif
  execute printf('doautocmd <nomodeline> User DenopsPluginPost:%s', l:plugin)
endfunction

function! s:DenopsSystemPluginFail() abort
  let l:plugin = matchstr(expand('<amatch>'), 'DenopsSystemPluginFail:\zs.*')
  let s:loaded_plugins[l:plugin] = -3
  if has_key(s:load_callbacks, l:plugin)
    call remove(s:load_callbacks, l:plugin)
  endif
  execute printf('doautocmd <nomodeline> User DenopsPluginFail:%s', l:plugin)
endfunction

augroup denops_autoload_plugin_internal
  autocmd!
  autocmd User DenopsSystemPluginRegister:* call s:DenopsSystemPluginRegister()
  autocmd User DenopsSystemPluginPre:* call s:DenopsSystemPluginPre()
  autocmd User DenopsSystemPluginPost:* call s:DenopsSystemPluginPost()
  autocmd User DenopsSystemPluginFail:* call s:DenopsSystemPluginFail()
  autocmd User DenopsClosed let s:loaded_plugins = {}
augroup END

call denops#_internal#conf#define('denops#plugin#wait_interval', 200)
call denops#_internal#conf#define('denops#plugin#wait_timeout', 30000)
