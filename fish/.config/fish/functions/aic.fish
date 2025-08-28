function aic --description 'Generate commit message from staged diff'
    set diff (git diff --staged | string collect)

    if test -z "$diff"
        echo "Nothing staged."
        return 1
    end

    set model "gpt-oss:120b"

    set prompt "Write a consise Tim Pope-style git commit message in the
    imperative present tense ('Fix bug', not 'Fixed bug'), starting with a
    single-line summary (max ~50 characters, no trailing punctuation,
    capitalized). Use clear and terse language. Don't waffle, keep it short.
    Don't use markdown. The title briefly encapsulates 'What' and the body
    'Why'. These are the changes:\n$diff"

    ollama run $model "$prompt"
end
