function stssh
  fish -c "sleep 0.1; open http://localhost:$argv[1]" &
  ssh -N -L $argv[1]:127.0.0.1:8384 $argv[2]
end
