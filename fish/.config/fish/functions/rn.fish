function rn
  if test (count $argv) -eq 0
    echo "Usage: rn <filename>"
    return 1
  end

  set ORIG_FILE $argv[1]

  if not test -e $ORIG_FILE
    echo "File '$ORIG_FILE' does not exist."
    return 1
  end

  read --prompt-str "rename> " --shell --command $ORIG_FILE --local NEW_FILE

  if test -z "$NEW_FILE"
    echo "No new file name provided. Exiting."
    return 1
  end

  mv $ORIG_FILE $NEW_FILE
end
