function ta --description "Attach to tmux session 'main' or create it"
    if tmux has-session -t main 2>/dev/null
        tmux attach-session -t main
    else
        tmux new-session -s main
    end
end
