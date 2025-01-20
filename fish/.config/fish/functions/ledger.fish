function ledger
    docker run --rm -v "$PWD":/data -w /data dcycle/ledger:1 $argv
end
