TMUX CHEATSHEET
===============

SESSIONS
  tmux new -s name       new named session
  tmux attach -t name    reattach to session
  tmux ls                list sessions
  Ctrl+b d               detach (leave running)

WINDOWS
  Ctrl+b c               new window
  Ctrl+b ,               rename window
  Ctrl+b n / p           next / prev window
  Ctrl+b 1-9             jump to window by number
  Ctrl+b x               kill pane

PANES
  Ctrl+b |               split vertical
  Ctrl+b -               split horizontal
  Ctrl+b arrows          move between panes
  Ctrl+b z               zoom pane (toggle fullscreen)

SCROLLING
  Ctrl+b [               enter scroll mode
  arrows                 scroll
  q                      exit scroll mode

MISC
  Ctrl+b :move-window -r    renumber all windows from 1
