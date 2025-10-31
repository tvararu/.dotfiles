function ta --description "Attach to tmux session 'main' or create it"
    tmux has-session -t main 2>/dev/null
    and tmux attach-session -t main
    or tmux new-session -d -s main; and tmux attach-session -t main
end
