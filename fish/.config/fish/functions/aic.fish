function aic --description 'Generate commit message from staged diff'
    set diff (git diff --staged | string collect)

    if test -z "$diff"
        echo "Nothing staged."
        return 1
    end

    set model "devstral"

    set prompt "Write a consise Tim Pope-style git commit message in the
  imperative present tense ('Fix bug', not 'Fixed bug'), starting with a
  single-line summary (max ~50 characters, no trailing punctuation,
  capitalized). Always follow with a blank line and body text wrapped at 72
  characters per line. Use clear, consistent language. Don't waffle, keep it
  short. The title briefly encapsulates 'What' and the body 'Why'. These are
  the changes:\n$diff"

    ollama run $model "$prompt"
end
